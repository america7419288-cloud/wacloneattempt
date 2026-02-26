const { 
    default: makeWASocket, 
    useMultiFileAuthState, 
    DisconnectReason, 
    fetchLatestBaileysVersion 
} = require('@whiskeysockets/baileys');
const admin = require('firebase-admin');
const qrcode = require('qrcode-terminal');
const { Boom } = require('@hapi/boom');

// 1. Connect to Firebase
const serviceAccount = require("./serviceAccountKey.json");
if (!admin.apps.length) {
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

async function startWhatsApp() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info');
    const { version } = await fetchLatestBaileysVersion();

    const sock = makeWASocket({
        version,
        auth: state,
        printQRInTerminal: false,
        browser: ["Mac OS", "Chrome", "10.15.7"],
    });

    sock.ev.on('creds.update', saveCreds);

    // 2. Handle Connection & QR
    sock.ev.on('connection.update', (update) => {
        const { connection, lastDisconnect, qr } = update;
        if (qr) {
            console.log('SCAN THIS QR CODE WITH WHATSAPP:');
            qrcode.generate(qr, { small: true });
        }

        if (connection === 'close') {
            const shouldReconnect = (lastDisconnect.error instanceof Boom) 
                ? lastDisconnect.error.output.statusCode !== DisconnectReason.loggedOut 
                : true;
            if (shouldReconnect) startWhatsApp();
        } else if (connection === 'open') {
            console.log('✅ Success! WhatsApp is connected.');
            
            // START LISTENING TO OUTBOX ONCE CONNECTED
            listenToOutbox(sock);
        }
    });

    // 3. Receive Messages & Update Contacts (For your Sidebar/ChatsList)
    sock.ev.on('messages.upsert', async ({ messages }) => {
        const msg = messages[0];
        if (!msg.message) return;

        const jid = msg.key.remoteJid;
        const text = msg.message.conversation || msg.message.extendedTextMessage?.text;

        if (text) {
            // Save Message (Matches your Flutter field names)
            await db.collection('messages').add({
                chatId: jid,
                from: jid,
                text: text, // Flutter uses 'text', not 'content'
                isMe: msg.key.fromMe,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Update Contact List (So your Flutter list shows the latest message)
            await db.collection('contacts').doc(jid).set({
                id: jid,
                name: msg.pushName || jid.split('@')[0],
                lastMessage: text,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                avatarLetter: (msg.pushName || 'U').charAt(0).toUpperCase()
            }, { merge: true });

            console.log(`📩 Message from ${jid} saved.`);
        }
    });
}

// 4. THE OUTBOX LISTENER (Sends messages from Flutter to WhatsApp)
function listenToOutbox(sock) {
    console.log('📡 Listening for outgoing messages from Flutter...');
    
    db.collection('outbox').where('status', '==', 'pending').onSnapshot(snapshot => {
        snapshot.docChanges().forEach(async (change) => {
            if (change.type === 'added') {
                const data = change.doc.data();
                const docId = change.doc.id;

                try {
                    console.log(`🚀 Sending message to ${data.to}...`);
                    
                    // Actually send the message via WhatsApp
                    await sock.sendMessage(data.to, { text: data.text });

                    // Update Firestore so we don't send it twice
                    await db.collection('outbox').doc(docId).update({ 
                        status: 'sent',
                        sentAt: admin.firestore.FieldValue.serverTimestamp() 
                    });

                    // Also add to messages collection so it appears in your UI
                    await db.collection('messages').add({
                        chatId: data.to,
                        text: data.text,
                        from: 'me',
                        isMe: true,
                        timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    });

                } catch (error) {
                    console.error("❌ Failed to send message:", error);
                    await db.collection('outbox').doc(docId).update({ status: 'error' });
                }
            }
        });
    });
}

startWhatsApp();