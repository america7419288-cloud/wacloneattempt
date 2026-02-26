const { 
    default: makeWASocket, 
    useMultiFileAuthState, 
    DisconnectReason, 
    fetchLatestBaileysVersion,
    downloadMediaMessage 
} = require('@whiskeysockets/baileys');
const admin = require('firebase-admin');
const qrcode = require('qrcode-terminal');
const { Boom } = require('@hapi/boom');
const cloudinary = require('cloudinary').v2;

// 1. CLOUDINARY CONFIGURATION
cloudinary.config({ 
  cloud_name: 'druwafmub', 
  api_key: '542473722884225', 
  api_secret: 'cD2OobWvCFwJvOSIYEDL1gl-fUY' 
});

// 2. FIREBASE CONFIGURATION
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

    // 3. CONNECTION HANDLER
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
            listenToOutbox(sock);
            listenToAddressBook(sock);
            listenToStoryOutbox(sock);
        }
    });

    // 4. PRESENCE UPDATES
    sock.ev.on('presence.update', async ({ id, presences }) => {
        const userPresence = presences[id];
        if (userPresence) {
            await db.collection('contacts').doc(id.toLowerCase()).set({
                presence: userPresence.lastKnownPresence, 
                lastSeen: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
        }
    });

    // 5. INCOMING MESSAGES & STATUS HANDLER
    sock.ev.on('messages.upsert', async ({ messages }) => {
        const msg = messages[0];
        if (!msg.message) return;

        // FIX 1: Normalize JID to lowercase to prevent duplicates
        const jid = msg.key.remoteJid.toLowerCase();
        
        // FIX 2: Lookup existing contact to prevent names reverting to numbers
        const contactDoc = await db.collection('contacts').doc(jid).get();
        let senderName = "";

        if (contactDoc.exists && contactDoc.data().name) {
            senderName = contactDoc.data().name; 
        } else {
            senderName = msg.pushName || jid.split('@')[0];
        }

        // --- HANDLE STATUS UPDATES (STORIES) ---
        if (jid === 'status@broadcast') {
            if (msg.key.fromMe) return; 

            const statusSender = msg.key.participant || "";
            const statusName = msg.pushName || (statusSender ? statusSender.split('@')[0] : "Unknown Status");
            let mediaUrl = "";

            const type = Object.keys(msg.message)[0];
            if (type === 'imageMessage' || type === 'videoMessage') {
                try {
                    const buffer = await downloadMediaMessage(msg, 'buffer', {});
                    const uploadResponse = await new Promise((resolve, reject) => {
                        cloudinary.uploader.upload_stream({ resource_type: 'auto', folder: 'stories' }, (error, result) => {
                            if (error) reject(error);
                            else resolve(result);
                        }).end(buffer);
                    });
                    mediaUrl = uploadResponse.secure_url;
                } catch (err) { console.error("Cloudinary Error:", err); }
            }

            const textStatus = msg.message.conversation || msg.message.extendedTextMessage?.text || "";
            
            await db.collection('stories').add({
                userId: statusSender,
                userName: statusName,
                text: textStatus,
                url: mediaUrl,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });
            return; 
        }

        // --- HANDLE REGULAR CHATS ---
        const text = msg.message.conversation || msg.message.extendedTextMessage?.text;

        if (text) {
            await db.collection('messages').add({
                chatId: jid,
                from: jid,
                text: text,
                senderName: senderName, 
                isMe: msg.key.fromMe,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
            });

            // FIX 3: Use .set with { merge: true } to update existing documents instead of creating new ones
            await db.collection('contacts').doc(jid).set({
                jid: jid,
                name: senderName, 
                lastMessage: text,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                avatarLetter: senderName.charAt(0).toUpperCase()
            }, { merge: true });
        }
    });
}

// 6. ADDRESS BOOK SYNCER
function listenToAddressBook(sock) {
    db.collection('address_book').onSnapshot(async (snapshot) => {
        for (const change of snapshot.docChanges()) {
            if (change.type === 'added') {
                const { phone, name } = change.doc.data();
                try {
                    const [result] = await sock.onWhatsApp(phone);
                    if (result && result.exists) {
                        const normalizedJid = result.jid.toLowerCase();
                        await db.collection('contacts').doc(normalizedJid).set({
                            jid: normalizedJid,
                            name: name,
                            avatarLetter: name.charAt(0).toUpperCase(),
                            timestamp: admin.firestore.FieldValue.serverTimestamp()
                        }, { merge: true });
                    }
                } catch (e) { console.error("Sync error:", e); }
                await change.doc.ref.delete(); 
            }
        }
    });
}

// 7. MESSAGE OUTBOX
function listenToOutbox(sock) {
    db.collection('outbox').where('status', '==', 'pending').onSnapshot(snapshot => {
        snapshot.docChanges().forEach(async (change) => {
            if (change.type === 'added') {
                const data = change.doc.data();
                const docId = change.doc.id;
                try {
                    await sock.sendMessage(data.to, { text: data.text });
                    await db.collection('outbox').doc(docId).update({ 
                        status: 'sent',
                        sentAt: admin.firestore.FieldValue.serverTimestamp() 
                    });
                    
                    const jid = data.to.toLowerCase();
                    await db.collection('messages').add({
                        chatId: jid,
                        text: data.text,
                        from: 'me',
                        fromMe: true, 
                        timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    });
                } catch (error) {
                    await db.collection('outbox').doc(docId).update({ status: 'error' });
                }
            }
        });
    });
}

// 8. STORY OUTBOX (Status Uploads)
function listenToStoryOutbox(sock) {
    db.collection('outbox_stories').where('status', '==', 'pending').onSnapshot(snapshot => {
        snapshot.docChanges().forEach(async (change) => {
            if (change.type === 'added') {
                const data = change.doc.data();
                const docId = change.doc.id;
                try {
                    await sock.sendMessage('status@broadcast', { 
                        image: { url: data.url }, 
                        caption: data.caption || '' 
                    });
                    await db.collection('outbox_stories').doc(docId).update({ 
                        status: 'sent',
                        sentAt: admin.firestore.FieldValue.serverTimestamp() 
                    });
                } catch (error) {
                    await db.collection('outbox_stories').doc(docId).update({ status: 'error' });
                }
            }
        });
    });
}

startWhatsApp();