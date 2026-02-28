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
const { createClient } = require('@supabase/supabase-js');
const { getLinkPreview } = require('link-preview-js');

// URL detection helper
function extractUrl(text) {
    if (!text) return null;
    const match = text.match(/(https?:\/\/[^\s]+)/i);
    return match ? match[0] : null;
}

// 1. SUPABASE STORAGE CONFIGURATION
const supabase = createClient(
    'https://ooopunhwxoffnfuawmmy.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9vb3B1bmh3eG9mZm5mdWF3bW15Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIxOTUyMzcsImV4cCI6MjA4Nzc3MTIzN30.qTyNjiDymtQhdruqvpcWQx-TIyxL2YK-k4rODtO9TcY'
);
const SUPABASE_BUCKET = 'whatsapp-media';

// 2. FIREBASE CONFIGURATION
const serviceAccount = require("./serviceAccountKey.json");
if (!admin.apps.length) {
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

// CRITICAL FIX: Enable ignoreUndefinedProperties to prevent crashes
const db = admin.firestore();
db.settings({ ignoreUndefinedProperties: true });

let reconnectDelay = 2000;
let unsubscribers = [];
let listenersStarted = false;

// --- SUPABASE PREPARATION ---
async function uploadToSupabaseWithRetry(path, buffer, options, retries = 3) {
    for (let i = 0; i <= retries; i++) {
        try {
            const { data, error } = await supabase.storage
                .from(SUPABASE_BUCKET)
                .upload(path, buffer, options);
            if (error) throw error;
            return data;
        } catch (err) {
            if (i === retries) {
                console.error(`Final upload attempt failed for ${path}: ${err.message}`);
                throw err;
            }
            console.log(`Upload to ${path} failed (${err.message}), retrying ${i + 1}/${retries}...`);
            await new Promise(res => setTimeout(res, 2000 + (i * 1000))); // Backoff
        }
    }
}

async function fetchAndStoreProfilePic(jid, sock) {
    try {
        const url = await sock.profilePictureUrl(jid, 'image');
        const response = await fetch(url);
        const buffer = Buffer.from(await response.arrayBuffer());
        const path = `profile_pics/${jid.replace('@', '_')}.jpg`;
        await uploadToSupabaseWithRetry(path, buffer, { contentType: 'image/jpeg', upsert: true });
        const { data } = supabase.storage.from(SUPABASE_BUCKET).getPublicUrl(path);
        return data.publicUrl;
    } catch (e) { return ''; }
}

async function startWhatsApp() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info');
    const { version } = await fetchLatestBaileysVersion();

    const sock = makeWASocket({
        version,
        auth: state,
        printQRInTerminal: false,
        browser: ["Mac OS", "Chrome", "10.15.7"],
        syncFullHistory: true,
        shouldSyncHistoryMessage: () => true,
    });

    sock.ev.on('creds.update', saveCreds);

    // --- SYNC PROGRESS HELPER ---
    async function updateSyncProgress(total, processed, syncing) {
        await db.collection('app_status').doc('sync_progress').set({
            totalMessages: total,
            processedMessages: processed,
            isSyncing: syncing,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    }

    // --- HISTORY SYNC LISTENER ---
    sock.ev.on('messaging-history.set', async ({ messages: historyMessages, isLatest }) => {
        console.log(`📜 History batch received: ${historyMessages.length} messages (isLatest: ${isLatest})`);

        // --- 1. PRE-SAVE CONTACT NAMES ---
        const contactUpdates = new Map();
        for (const msg of historyMessages) {
            if (!msg.key || !msg.message) continue;
            const jid = (msg.key.remoteJid || '').toLowerCase();
            const name = msg.pushName;
            const invalidJids = ['status@broadcast', '@newsletter', '@lid', '@broadcast'];
            if (invalidJids.some(suffix => jid === suffix || jid.endsWith(suffix))) continue;
            if (jid && name) {
                contactUpdates.set(jid, name);
            }
        }
        for (const [jid, name] of contactUpdates.entries()) {
            let profileUrl = '';
            const isGroup = jid.endsWith('@g.us');

            let finalName = name;
            try {
                const doc = await db.collection('contacts').doc(jid).get();
                if (doc.exists && doc.data().name) {
                    finalName = doc.data().name;
                }
            } catch (e) { }

            // --- GROUP METADATA ---
            if (isGroup) {
                try {
                    const groupMeta = await sock.groupMetadata(jid);
                    const groupPayload = {
                        jid: jid,
                        name: groupMeta.subject || finalName,
                        isGroup: true,
                        avatarLetter: (groupMeta.subject || finalName).charAt(0).toUpperCase(),
                        onlyAdminsCanMessage: groupMeta.announce || false,
                    };
                    const gpic = await fetchAndStoreProfilePic(jid, sock);
                    if (gpic) { groupPayload.profileUrl = gpic; groupPayload.lastPicUpdate = admin.firestore.FieldValue.serverTimestamp(); }
                    await db.collection('contacts').doc(jid).set(groupPayload, { merge: true });
                } catch (gErr) {
                    console.log(`Could not fetch group metadata for ${jid}`);
                }
                continue;
            }

            // --- INDIVIDUAL CONTACT ---
            profileUrl = await fetchAndStoreProfilePic(jid, sock);

            const updatePayload = {
                jid: jid,
                name: finalName,
                avatarLetter: name.charAt(0).toUpperCase()
            };

            if (profileUrl) {
                updatePayload.profileUrl = profileUrl;
                updatePayload.lastPicUpdate = admin.firestore.FieldValue.serverTimestamp();
            }

            await db.collection('contacts').doc(jid).set(updatePayload, { merge: true });
        }

        // --- 2. TIME FILTER (LAST 14 DAYS) ---
        const cutoffDate = new Date();
        cutoffDate.setDate(cutoffDate.getDate() - 14);
        const cutoffMs = cutoffDate.getTime();

        const filteredMessages = historyMessages.filter(msg => {
            if (!msg.messageTimestamp) return false;
            let msgMs = typeof msg.messageTimestamp === 'number'
                ? msg.messageTimestamp * 1000
                : Number(msg.messageTimestamp) * 1000;
            return msgMs >= cutoffMs;
        });

        const totalInBatch = filteredMessages.length;
        console.log(`⏳ After 14-day filter: ${totalInBatch} messages to process.`);
        let processedInBatch = 0;

        await updateSyncProgress(totalInBatch, 0, true);

        // BULK DUPLICATE CHECK — fetch all existing msgKeyIds into a Set
        const existingSnap = await db.collection('messages').select('msgKeyId').get();
        const existingIds = new Set(existingSnap.docs.map(d => d.data().msgKeyId).filter(Boolean));

        for (const msg of filteredMessages) {
            try {
                if (!msg.message || !msg.key || !msg.key.id) {
                    processedInBatch++;
                    continue;
                }

                const msgKeyId = msg.key.id;

                // DUPLICATE CHECK using in-memory Set
                if (existingIds.has(msgKeyId)) {
                    processedInBatch++;
                    if (processedInBatch % 50 === 0) {
                        await updateSyncProgress(totalInBatch, processedInBatch, true);
                    }
                    continue;
                }
                existingIds.add(msgKeyId); // prevent duplicates within same batch

                const jid = (msg.key.remoteJid || '').toLowerCase();
                const invalidJids = ['status@broadcast', '@newsletter', '@lid', '@broadcast'];
                if (!jid || invalidJids.some(suffix => jid === suffix || jid.endsWith(suffix))) {
                    processedInBatch++;
                    continue;
                }

                const isMe = msg.key.fromMe || false;
                const senderName = msg.pushName || jid.split('@')[0];
                const msgTimestamp = msg.messageTimestamp
                    ? new Date(typeof msg.messageTimestamp === 'number'
                        ? msg.messageTimestamp * 1000
                        : Number(msg.messageTimestamp) * 1000)
                    : null;

                const type = Object.keys(msg.message)[0];
                const mediaTypes = ['imageMessage', 'videoMessage', 'audioMessage', 'documentMessage'];

                const docData = {
                    chatId: jid,
                    from: isMe ? 'me' : jid,
                    isMe: isMe,
                    senderName: senderName,
                    msgKeyId: msgKeyId,
                    timestamp: msgTimestamp || admin.firestore.FieldValue.serverTimestamp(),
                };

                // --- REPLY CONTEXT ---
                const ctxInfo = msg.message?.extendedTextMessage?.contextInfo;
                if (ctxInfo && ctxInfo.quotedMessage) {
                    const quotedText = ctxInfo.quotedMessage.conversation
                        || ctxInfo.quotedMessage.extendedTextMessage?.text
                        || ctxInfo.quotedMessage.imageMessage?.caption
                        || '';
                    const authorJid = ctxInfo.participant || '';
                    let authorName = authorJid.split('@')[0];
                    if (authorJid) {
                        try {
                            const authorDoc = await db.collection('contacts').doc(authorJid).get();
                            if (authorDoc.exists && authorDoc.data().name) {
                                authorName = authorDoc.data().name;
                            }
                        } catch (e) { /* skip lookup */ }
                    }
                    docData.replyTo = {
                        text: quotedText,
                        author: authorName,
                    };
                }

                if (mediaTypes.includes(type)) {
                    // --- MEDIA MESSAGE & LIMITS ---
                    const typeMap = {
                        imageMessage: 'image',
                        videoMessage: 'video',
                        audioMessage: 'audio',
                        documentMessage: 'file',
                    };
                    const contentTypeMap = {
                        imageMessage: 'image/jpeg',
                        videoMessage: 'video/mp4',
                        audioMessage: 'audio/ogg',
                        documentMessage: 'application/octet-stream',
                    };
                    const mediaObj = msg.message[type];

                    // Optional chaining mostly works but fileLength comes as Long or number
                    let fileLength = 0;
                    if (mediaObj?.fileLength) {
                        fileLength = typeof mediaObj.fileLength === 'number'
                            ? mediaObj.fileLength
                            : Number(mediaObj.fileLength);
                    }

                    if (fileLength > 50 * 1024 * 1024) { // 50MB limit
                        docData.type = 'large_file_skipped';
                        docData.text = mediaObj?.caption || '';
                        docData.mediaUrl = '';
                        console.log(`⚠️ Skipped large file (${fileLength} bytes) for ${msgKeyId}`);
                    } else {
                        docData.type = typeMap[type];
                        docData.text = mediaObj?.caption || '';
                        if (type === 'documentMessage') {
                            docData.fileName = mediaObj?.fileName || 'document';
                        }

                        try {
                            const buffer = await downloadMediaMessage(msg, 'buffer', {});
                            const filePath = `wa_history/${msgKeyId}_${Date.now()}`;
                            await uploadToSupabaseWithRetry(filePath, buffer, {
                                contentType: contentTypeMap[type] || 'application/octet-stream',
                                upsert: true,
                            });
                            const { data: urlData } = supabase.storage
                                .from(SUPABASE_BUCKET)
                                .getPublicUrl(filePath);
                            docData.mediaUrl = urlData?.publicUrl || '';
                        } catch (mediaErr) {
                            console.error(`⚠️ Media upload failed for ${msgKeyId}:`, mediaErr.message);
                            docData.mediaUrl = '';
                        }
                    }
                } else {
                    // --- TEXT MESSAGE ---
                    const text = msg.message.conversation
                        || msg.message.extendedTextMessage?.text
                        || '';
                    if (!text) {
                        processedInBatch++;
                        continue;
                    }
                    docData.text = text;

                    // --- LINK PREVIEW ---
                    const url = extractUrl(text);
                    if (url) {
                        try {
                            const preview = await getLinkPreview(url, { timeout: 5000 });
                            docData.linkPreview = {
                                title: preview.title || '',
                                description: preview.description || '',
                                image: (preview.images && preview.images[0]) || preview.favicons?.[0] || '',
                                url: url,
                            };
                        } catch (lpErr) { /* link preview fetch failed, skip */ }
                    }
                }

                await db.collection('messages').add(docData);

                // Update contact entry for last message
                await db.collection('contacts').doc(jid).set({
                    jid: jid,
                    lastMessage: docData.text || `[${docData.type || 'media'}]`,
                    timestamp: docData.timestamp,
                    avatarLetter: senderName.charAt(0).toUpperCase(),
                }, { merge: true });

            } catch (err) {
                console.error('History msg error:', err.message);
            }

            processedInBatch++;
            if (processedInBatch % 50 === 0) {
                await updateSyncProgress(totalInBatch, processedInBatch, true);
                console.log(`   ⏳ Progress: ${processedInBatch}/${totalInBatch}`);
            }
        }

        await updateSyncProgress(totalInBatch, processedInBatch, !isLatest);
        console.log(`✅ History batch done: ${processedInBatch}/${totalInBatch} processed. Final: ${isLatest}`);
    });

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
            if (shouldReconnect) {
                console.log(`Reconnecting in ${reconnectDelay}ms...`);
                setTimeout(() => startWhatsApp(), reconnectDelay);
                reconnectDelay = Math.min(reconnectDelay * 2, 60000); // max 60s
            }
        } else if (connection === 'open') {
            console.log('✅ Success! WhatsApp is connected.');
            reconnectDelay = 2000;
            if (listenersStarted) {
                unsubscribers.forEach(unsub => unsub());
                unsubscribers = [];
            }
            listenersStarted = true;
            // Call listeners now that connection is open
            unsubscribers.push(listenToOutbox(sock));
            unsubscribers.push(listenToAddressBook(sock));
            unsubscribers.push(listenToStoryOutbox(sock));
            unsubscribers.push(listenToCommands(sock));
            unsubscribers.push(listenToReactionOutbox(sock));
        }
    });

    // 4. INCOMING MESSAGES & IDENTITY SYNC
    sock.ev.on('messages.upsert', async ({ messages }) => {
        for (const msg of messages) {
            if (!msg || !msg.message) continue;

            // Force JID to lowercase for consistency
            const jid = msg.key.remoteJid.toLowerCase();

            if (jid !== 'status@broadcast') {
                const invalidJids = ['@newsletter', '@lid', '@broadcast'];
                if (invalidJids.some(suffix => jid.endsWith(suffix))) continue;
            }

            // LOOKUP: Check if we have a saved name/pic to prevent bugs
            const contactDoc = await db.collection('contacts').doc(jid).get();
            let savedPic = "";
            let lastPicUpdate = 0;

            if (contactDoc.exists) {
                const data = contactDoc.data();
                savedPic = data.profileUrl || "";
                if (data.lastPicUpdate) {
                    lastPicUpdate = data.lastPicUpdate.toMillis();
                }
            }

            let senderName = contactDoc.exists
                ? (contactDoc.data().name || msg.pushName || jid.split('@')[0])
                : (msg.pushName || jid.split('@')[0]);

            // --- FETCH PROFILE PICTURE ---
            let profilePic = savedPic;
            const now = Date.now();
            // 24 hours = 86400000 ms
            let newlyFetchedPic = false;
            if (now - lastPicUpdate > 86400000 || !savedPic) {
                const url = await fetchAndStoreProfilePic(jid, sock);
                profilePic = url || "";
                newlyFetchedPic = true;
            }

            // --- HANDLE STATUS UPDATES ---
            if (jid === 'status@broadcast') {
                if (msg.key.fromMe) return;
                const statusSender = msg.key.participant || "";
                const statusName = msg.pushName || (statusSender ? statusSender.split('@')[0] : "Unknown Status");
                let mediaUrl = "";

                const type = Object.keys(msg.message)[0];
                if (type === 'imageMessage' || type === 'videoMessage') {
                    try {
                        const buffer = await downloadMediaMessage(msg, 'buffer', {});
                        const storyContentType = type === 'videoMessage' ? 'video/mp4' : 'image/jpeg';
                        const storyPath = `stories/${msg.key.id}_${Date.now()}`;
                        await uploadToSupabaseWithRetry(storyPath, buffer, {
                            contentType: storyContentType,
                            upsert: true,
                        });
                        const { data: storyUrlData } = supabase.storage
                            .from(SUPABASE_BUCKET)
                            .getPublicUrl(storyPath);
                        mediaUrl = storyUrlData?.publicUrl || "";
                    } catch (err) { console.error("Supabase Upload Error:", err); }
                }

                if (mediaUrl || msg.message.conversation) {
                    await db.collection('stories').add({
                        senderId: statusSender,
                        senderName: statusName,
                        text: msg.message.conversation || "",
                        url: mediaUrl,
                        timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    });
                } else {
                    console.log('Skipping empty story upload');
                }
                return;
            }

            // --- HANDLE REGULAR & MEDIA MESSAGES ---
            const type = Object.keys(msg.message)[0];
            const mediaTypes = ['imageMessage', 'videoMessage', 'audioMessage', 'documentMessage'];
            const text = msg.message.conversation || msg.message.extendedTextMessage?.text;
            const msgKeyId = msg.key.id || '';

            if (msgKeyId) {
                const existing = await db.collection('messages')
                    .where('msgKeyId', '==', msgKeyId)
                    .limit(1)
                    .get();
                if (!existing.empty) return;
            }

            if (text || mediaTypes.includes(type)) {
                const msgData = {
                    chatId: jid,
                    from: jid,
                    senderName: senderName,
                    isMe: msg.key.fromMe,
                    msgKeyId: msgKeyId,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                };

                // --- REPLY CONTEXT ---
                const ctxInfo = msg.message?.extendedTextMessage?.contextInfo;
                if (ctxInfo && ctxInfo.quotedMessage) {
                    const quotedText = ctxInfo.quotedMessage.conversation
                        || ctxInfo.quotedMessage.extendedTextMessage?.text
                        || ctxInfo.quotedMessage.imageMessage?.caption
                        || '';
                    const authorJid = ctxInfo.participant || '';
                    let rtAuthorName = authorJid.split('@')[0];
                    if (authorJid) {
                        try {
                            const authorDoc = await db.collection('contacts').doc(authorJid).get();
                            if (authorDoc.exists && authorDoc.data().name) {
                                rtAuthorName = authorDoc.data().name;
                            }
                        } catch (e) { /* skip lookup */ }
                    }
                    msgData.replyTo = {
                        text: quotedText,
                        author: rtAuthorName,
                    };
                }

                if (mediaTypes.includes(type)) {
                    const typeMap = {
                        imageMessage: 'image',
                        videoMessage: 'video',
                        audioMessage: 'audio',
                        documentMessage: 'file',
                    };
                    msgData.type = typeMap[type];
                    msgData.text = msg.message[type]?.caption || '';
                    if (type === 'documentMessage') {
                        msgData.fileName = msg.message[type]?.fileName || 'document';
                    }
                    try {
                        const buffer = await downloadMediaMessage(msg, 'buffer', {});
                        const rtContentTypeMap = {
                            imageMessage: 'image/jpeg',
                            videoMessage: 'video/mp4',
                            audioMessage: 'audio/ogg',
                            documentMessage: 'application/octet-stream',
                        };
                        const rtPath = `wa_media/${msg.key.id}_${Date.now()}`;
                        await uploadToSupabaseWithRetry(rtPath, buffer, {
                            contentType: rtContentTypeMap[type] || 'application/octet-stream',
                            upsert: true,
                        });
                        const { data: rtUrlData } = supabase.storage
                            .from(SUPABASE_BUCKET)
                            .getPublicUrl(rtPath);
                        msgData.mediaUrl = rtUrlData?.publicUrl || '';
                    } catch (mediaErr) {
                        console.error('⚠️ Real-time media upload failed:', mediaErr.message);
                        msgData.mediaUrl = '';
                    }
                } else {
                    msgData.text = text;

                    // --- LINK PREVIEW ---
                    const linkUrl = extractUrl(text);
                    if (linkUrl) {
                        try {
                            const preview = await getLinkPreview(linkUrl, { timeout: 5000 });
                            msgData.linkPreview = {
                                title: preview.title || '',
                                description: preview.description || '',
                                image: (preview.images && preview.images[0]) || preview.favicons?.[0] || '',
                                url: linkUrl,
                            };
                        } catch (lpErr) { /* skip */ }
                    }
                }

                await db.collection('messages').add(msgData);

                const lastMsgPreview = msgData.text || `[${msgData.type || 'media'}]`;
                const isGroup = jid.endsWith('@g.us');
                const updatePayload = {
                    jid: jid,
                    name: senderName,
                    profileUrl: profilePic,
                    lastMessage: lastMsgPreview,
                    timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    avatarLetter: senderName.charAt(0).toUpperCase()
                };
                if (newlyFetchedPic) {
                    updatePayload.lastPicUpdate = admin.firestore.FieldValue.serverTimestamp();
                }
                // Detect groups in real-time
                if (isGroup) {
                    updatePayload.isGroup = true;
                    try {
                        const gm = await sock.groupMetadata(jid);
                        updatePayload.name = gm.subject || senderName;
                        updatePayload.onlyAdminsCanMessage = gm.announce || false;
                        updatePayload.avatarLetter = (gm.subject || senderName).charAt(0).toUpperCase();
                    } catch (e) { /* skip metadata fetch error */ }
                }
                // Increment unread count for incoming messages
                if (!msg.key.fromMe) {
                    updatePayload.unreadCount = admin.firestore.FieldValue.increment(1);
                }

                await db.collection('contacts').doc(jid).set(updatePayload, { merge: true });
            }
        } // end for-loop over messages
    });

    // 4b. REACTIONS LISTENER
    sock.ev.on('messages.reaction', async (reactions) => {
        for (const reaction of reactions) {
            const key = reaction.key; // key of the message being reacted to
            const emoji = reaction.reaction?.text || '';
            const sender = reaction.reaction?.key?.participant || reaction.reaction?.key?.remoteJid || '';
            const targetMsgId = key?.id;
            if (!targetMsgId) continue;

            try {
                const snap = await db.collection('messages')
                    .where('msgKeyId', '==', targetMsgId)
                    .limit(1)
                    .get();
                if (!snap.empty) {
                    const docRef = snap.docs[0].ref;
                    if (emoji) {
                        // Add reaction
                        await docRef.update({
                            reactions: admin.firestore.FieldValue.arrayUnion({ emoji, sender })
                        });
                    } else {
                        // Remove reaction (empty emoji = reaction removed)
                        const existing = snap.docs[0].data().reactions || [];
                        const filtered = existing.filter(r => r.sender !== sender);
                        await docRef.update({ reactions: filtered });
                    }
                }
            } catch (e) {
                console.error('Reaction update error:', e.message);
            }
        }
    });

    // 4c. TYPING / PRESENCE INDICATORS
    sock.ev.on('presence.update', async ({ id, presences }) => {
        const jid = id.toLowerCase();
        const presence = Object.values(presences)[0];
        await db.collection('contacts').doc(jid).set({
            presence: presence?.lastKnownPresence || 'unavailable',
            presenceUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
    });

    // 4d. MESSAGE DELETION (delete for everyone)
    sock.ev.on('messages.update', async (updates) => {
        for (const update of updates) {
            if (update.update?.message === null || update.update?.messageStubType === 1) {
                const msgKeyId = update.key?.id;
                if (!msgKeyId) continue;
                const snap = await db.collection('messages').where('msgKeyId', '==', msgKeyId).limit(1).get();
                if (!snap.empty) {
                    await snap.docs[0].ref.update({ deleted: true, text: 'This message was deleted' });
                }
            }
        }
    });

    // 4e. DELIVERY AND READ RECEIPTS
    sock.ev.on('message-receipt.update', async (updates) => {
        for (const { key, receipt } of updates) {
            const msgKeyId = key?.id;
            if (!msgKeyId) continue;
            const snap = await db.collection('messages').where('msgKeyId', '==', msgKeyId).limit(1).get();
            if (!snap.empty) {
                const status = receipt.receiptTimestamp ? 'read' : receipt.playedTimestamp ? 'played' : 'delivered';
                await snap.docs[0].ref.update({ deliveryStatus: status });
            }
        }
    });
}

// 5. ADDRESS BOOK SYNCER
function listenToAddressBook(sock) {
    console.log('📖 Watching address_book for new contacts...');
    return db.collection('address_book').onSnapshot(async (snapshot) => {
        for (const change of snapshot.docChanges()) {
            if (change.type === 'added') {
                const { phone, name } = change.doc.data();
                try {
                    const [result] = await sock.onWhatsApp(phone);
                    if (result && result.exists) {
                        const normalizedJid = result.jid.toLowerCase();

                        // NEW: Explicitly fetch profile picture for the contact picker
                        let pic = await fetchAndStoreProfilePic(normalizedJid, sock);

                        await db.collection('contacts').doc(normalizedJid).set({
                            jid: normalizedJid,
                            name: name,
                            profileUrl: pic || "", // This field makes it visible in your list
                            avatarLetter: (name && name.length > 0) ? name.charAt(0).toUpperCase() : '?',
                            timestamp: admin.firestore.FieldValue.serverTimestamp()
                        }, { merge: true });

                        console.log(`✅ Verified and synced profile for ${name}`);
                    }
                } catch (e) { console.error("Sync error:", e); }
                await change.doc.ref.delete();
            }
        }
    });
}

// 6. MESSAGE OUTBOX
function listenToOutbox(sock) {
    console.log('📡 Listening for outgoing messages from Flutter...');
    return db.collection('outbox').where('status', '==', 'pending').onSnapshot(async (snapshot) => {
        for (const change of snapshot.docChanges()) {
            if (change.type === 'added') {
                const data = change.doc.data();
                const docId = change.doc.id;
                try {
                    let quotedMsg = undefined;
                    if (data.replyTo && data.replyTo.msgKeyId) {
                        try {
                            const quotedSnap = await db.collection('messages').where('msgKeyId', '==', data.replyTo.msgKeyId).limit(1).get();
                            if (!quotedSnap.empty) {
                                const qData = quotedSnap.docs[0].data();
                                quotedMsg = {
                                    key: { id: qData.msgKeyId, fromMe: qData.isMe, remoteJid: qData.chatId },
                                    message: { conversation: qData.text }
                                };
                            }
                        } catch (e) { console.error("Could not fetch quote context:", e); }
                    }

                    const sentMsg = await sock.sendMessage(data.to, { text: data.text }, { quoted: quotedMsg });

                    if (sentMsg && sentMsg.key && sentMsg.key.id) {
                        const matchSnap = await db.collection('messages')
                            .where('chatId', '==', data.to)
                            .where('isMe', '==', true)
                            .where('text', '==', data.text)
                            .get();
                        const match = matchSnap.docs.find(d => !d.data().msgKeyId);
                        if (match) {
                            await match.ref.update({ msgKeyId: sentMsg.key.id });
                        }
                    }

                    await db.collection('outbox').doc(docId).delete();
                } catch (error) {
                    await db.collection('outbox').doc(docId).update({ status: 'error' });
                }
            }
        }
    });
}

// 7. STORY OUTBOX
function listenToStoryOutbox(sock) {
    console.log('🌟 Listening for status uploads from Flutter...');
    return db.collection('outbox_stories').where('status', '==', 'pending').onSnapshot(async (snapshot) => {
        for (const change of snapshot.docChanges()) {
            if (change.type === 'added') {
                const data = change.doc.data();
                try {
                    console.log(`🚀 Posting new status to WhatsApp...`);
                    await sock.sendMessage('status@broadcast', {
                        image: { url: data.url },
                        caption: data.caption || ''
                    });
                    await db.collection('outbox_stories').doc(change.doc.id).delete();
                } catch (error) {
                    console.error("❌ Status upload failed:", error);
                    await db.collection('outbox_stories').doc(change.doc.id).update({ status: 'error' });
                }
            }
        }
    });
}

// 8. COMMANDS LISTENER
function listenToCommands(sock) {
    console.log('⚡ Listening for manual sync commands...');
    return db.collection('commands').onSnapshot(async (snapshot) => {
        for (const change of snapshot.docChanges()) {
            if (change.type === 'added') {
                const data = change.doc.data();

                if (data.type === 'REFRESH_PROFILES') {
                    console.log('🔄 Starting bulk profile & group metadata refresh...');
                    const contacts = await db.collection('contacts').get();

                    for (const doc of contacts.docs) {
                        const jid = doc.id;
                        const isGroup = jid.endsWith('@g.us');
                        const updatePayload = {};

                        // --- GROUP METADATA ---
                        if (isGroup) {
                            try {
                                const gm = await sock.groupMetadata(jid);
                                updatePayload.name = gm.subject || jid.split('@')[0];
                                updatePayload.isGroup = true;
                                updatePayload.onlyAdminsCanMessage = gm.announce || false;
                                updatePayload.avatarLetter = (gm.subject || 'G').charAt(0).toUpperCase();
                                console.log(`👥 Refreshed group: ${gm.subject}`);
                            } catch (gErr) {
                                console.log(`Could not fetch group metadata for ${jid}`);
                            }
                        }

                        // --- PROFILE PICTURE (both groups and individuals) ---
                        let profileUrl = await fetchAndStoreProfilePic(jid, sock);

                        if (profileUrl) {
                            updatePayload.profileUrl = profileUrl;
                            updatePayload.lastPicUpdate = admin.firestore.FieldValue.serverTimestamp();
                        }

                        if (Object.keys(updatePayload).length > 0) {
                            await db.collection('contacts').doc(jid).set(updatePayload, { merge: true });
                        }
                    }
                    console.log('✅ Bulk refresh complete.');
                }
                // Delete the command doc after processing
                await change.doc.ref.delete();
            }
        }
    });
}

// 9. REACTION OUTBOX LISTENER
function listenToReactionOutbox(sock) {
    console.log('😀 Listening for outgoing reactions...');
    return db.collection('outbox_reactions').where('status', '==', 'pending').onSnapshot(async (snapshot) => {
        for (const change of snapshot.docChanges()) {
            if (change.type === 'added') {
                const data = change.doc.data();
                try {
                    await sock.sendMessage(data.chatJid, {
                        react: {
                            text: data.emoji,
                            key: {
                                remoteJid: data.chatJid,
                                id: data.msgKeyId,
                                fromMe: data.fromMe || false,
                            }
                        }
                    });
                    await change.doc.ref.delete();
                    console.log(`✅ Sent reaction ${data.emoji} to ${data.msgKeyId}`);
                } catch (e) {
                    console.error('Reaction send error:', e.message);
                    await change.doc.ref.update({ status: 'error' });
                }
            }
        }
    });
}

startWhatsApp();