const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

/**
 * Helper function to send a push notification to a user
 */
async function sendPushToUser(userId, notification, data = {}) {
    try {
        const userDoc = await db.collection("users").doc(userId).get();
        if (!userDoc.exists) {
            console.log(`User ${userId} not found`);
            return;
        }

        const fcmToken = userDoc.data().fcmToken;
        if (!fcmToken) {
            console.log(`No FCM token for user ${userId}`);
            return;
        }

        const message = {
            token: fcmToken,
            notification: notification,
            data: data,
            android: {
                priority: "high",
                notification: {
                    sound: "default",
                    channelId: "idex_notifications",
                    clickAction: "FLUTTER_NOTIFICATION_CLICK",
                },
            },
            apns: {
                payload: {
                    aps: {
                        sound: "default",
                    },
                },
            },
        };

        await messaging.send(message);
        console.log(`Push sent to user ${userId}`);
    } catch (error) {
        console.error(`Error sending push to ${userId}:`, error);
    }
}

/**
 * UNIVERSAL TRIGGER: When any in-app notification is created
 * This catches ALL notifications (stars, comments, replies, etc.)
 */
exports.onNewNotification = functions.firestore
    .document("users/{userId}/notifications/{notifId}")
    .onCreate(async (snapshot, context) => {
        const { userId } = context.params;
        const notif = snapshot.data();

        // Send push notification with all relevant data for deep linking
        await sendPushToUser(userId, {
            title: notif.title || "New Notification",
            body: notif.message || "",
        }, {
            type: notif.type || "",
            ideaId: notif.ideaId || "",
            groupId: notif.groupId || "",
        });
    });

/**
 * Trigger: When a new idea is created in a group
 */
exports.onNewGroupIdea = functions.firestore
    .document("groups/{groupId}/ideas/{ideaId}")
    .onCreate(async (snapshot, context) => {
        const { groupId, ideaId } = context.params;
        const ideaData = snapshot.data();
        const authorId = ideaData.authorId;
        const ideaName = ideaData.name || "New Idea";
        const authorName = ideaData.authorName || "Someone";

        const membersSnapshot = await db
            .collection("groups")
            .doc(groupId)
            .collection("members")
            .get();

        const promises = membersSnapshot.docs
            .filter((doc) => doc.id !== authorId)
            .map((doc) => sendPushToUser(doc.id, {
                title: "New Idea in Your Group!",
                body: `${authorName} posted: "${ideaName}"`,
            }, {
                type: "new_group_idea",
                groupId: groupId,
                ideaId: ideaId,
            }));

        await Promise.all(promises);
    });

/**
 * Trigger: When a vote is added
 */
exports.onIdeaVote = functions.firestore
    .document("groups/{groupId}/ideas/{ideaId}/votes/{voterId}")
    .onCreate(async (snapshot, context) => {
        const { groupId, ideaId, voterId } = context.params;
        const voterName = snapshot.data().userName || "Someone";

        const ideaDoc = await db.collection("groups").doc(groupId).collection("ideas").doc(ideaId).get();
        if (!ideaDoc.exists) return;

        const authorId = ideaDoc.data().authorId;
        if (authorId === voterId) return;

        await sendPushToUser(authorId, {
            title: "New Upvote! ❤️",
            body: `${voterName} upvoted "${ideaDoc.data().name}"`,
        }, {
            type: "idea_vote",
            groupId: groupId,
            ideaId: ideaId,
        });
    });

/**
 * Trigger: When a Direct Group Invite is created
 */
exports.onGroupInviteCreated = functions.firestore
    .document("group_invites/{inviteId}")
    .onCreate(async (snapshot, context) => {
        const data = snapshot.data();
        await sendPushToUser(data.invitedUserId, {
            title: "Group Invitation! ✉️",
            body: `${data.invitedByName} invited you to join "${data.groupName}"`,
        }, {
            type: "group_invite",
            groupId: data.groupId,
        });
    });

/**
 * Trigger: When a Join Request is sent (via code)
 */
exports.onJoinRequestCreated = functions.firestore
    .document("groups/{groupId}/join_requests/{userId}")
    .onCreate(async (snapshot, context) => {
        const { groupId } = context.params;
        const requestData = snapshot.data();

        const groupDoc = await db.collection("groups").doc(groupId).get();
        if (!groupDoc.exists) return;

        await sendPushToUser(groupDoc.data().ownerId, {
            title: "New Join Request! 👋",
            body: `${requestData.userName} wants to join "${groupDoc.data().name}"`,
        }, {
            type: "join_request",
            groupId: groupId,
        });
    });

/**
 * Trigger: When a user joins or is added (covers acceptance of invite/request)
 */
exports.onMemberAdded = functions.firestore
    .document("groups/{groupId}/members/{userId}")
    .onCreate(async (snapshot, context) => {
        const { groupId, userId } = context.params;
        const memberData = snapshot.data();

        const groupDoc = await db.collection("groups").doc(groupId).get();
        if (!groupDoc.exists) return;

        const groupData = groupDoc.data();
        const ownerId = groupData.ownerId;

        // 1. Notify the new member
        if (userId !== ownerId) {
            await sendPushToUser(userId, {
                title: "Welcome! 🎉",
                body: `You are now a member of "${groupData.name}"`,
            }, { type: "member_added", groupId: groupId });

            // 2. Notify the owner/leader
            await sendPushToUser(ownerId, {
                title: "New member joined!",
                body: `${memberData.userName} is now in "${groupData.name}"`,
            }, { type: "member_joined", groupId: groupId });
        }
    });

/**
 * Trigger: When an idea is approved
 */
exports.onIdeaApproved = functions.firestore
    .document("groups/{groupId}/ideas/{ideaId}")
    .onUpdate(async (change, context) => {
        const { groupId, ideaId } = context.params;
        const before = change.before.data();
        const after = change.after.data();

        if (!before.isApproved && after.isApproved) {
            await sendPushToUser(after.authorId, {
                title: "Idea Approved! 🎊",
                body: `"${after.name}" has been approved!`,
            }, {
                type: "idea_approved",
                groupId: groupId,
                ideaId: ideaId,
            });
        }
    });

/**
 * Trigger: When a feature status changes
 */
exports.onFeatureStatusChanged = functions.firestore
    .document("groups/{groupId}/ideas/{ideaId}")
    .onUpdate(async (change, context) => {
        const beforeFeatures = change.before.data().features || [];
        const afterFeatures = change.after.data().features || [];

        for (let i = 0; i < afterFeatures.length; i++) {
            const beforeF = beforeFeatures.find(f => f.id === afterFeatures[i].id);
            if (beforeF && beforeF.status !== afterFeatures[i].status) {
                // Status changed! Notify author
                await sendPushToUser(change.after.data().authorId, {
                    title: "Feature Progress Updated! 🛠️",
                    body: `"${afterFeatures[i].name}" moved to ${afterFeatures[i].status}`,
                }, {
                    type: "feature_status",
                    groupId: context.params.groupId,
                    ideaId: context.params.ideaId,
                });
                break;
            }
        }
    });

/**
 * Trigger: When a Firebase Auth user is deleted
 * Automatically cleans up all Firestore data for that user
 */
exports.onUserDeleted = functions.auth.user().onDelete(async (user) => {
    const userId = user.uid;
    console.log(`User ${userId} deleted from Auth. Starting Firestore cleanup...`);

    try {
        const batch = db.batch();

        // 1. Delete user's private ideas subcollection
        const ideasSnap = await db.collection("users").doc(userId).collection("ideas").get();
        console.log(`Found ${ideasSnap.size} private ideas to delete`);
        ideasSnap.forEach(doc => batch.delete(doc.ref));

        // 2. Delete user's starred ideas subcollection
        const starredSnap = await db.collection("users").doc(userId).collection("starred_ideas").get();
        console.log(`Found ${starredSnap.size} starred ideas to delete`);
        starredSnap.forEach(doc => batch.delete(doc.ref));

        // 3. Delete user's notifications subcollection
        const notifsSnap = await db.collection("users").doc(userId).collection("notifications").get();
        console.log(`Found ${notifsSnap.size} notifications to delete`);
        notifsSnap.forEach(doc => batch.delete(doc.ref));

        // 4. Delete user document
        batch.delete(db.collection("users").doc(userId));

        // 5. Execute batch for user data
        await batch.commit();
        console.log(`User document and subcollections deleted for ${userId}`);

        // 6. Delete user's public ideas (separate batch)
        const publicIdeasSnap = await db.collection("public_ideas").where("ownerId", "==", userId).get();
        if (publicIdeasSnap.size > 0) {
            const publicBatch = db.batch();
            console.log(`Found ${publicIdeasSnap.size} public ideas to delete`);
            publicIdeasSnap.forEach(doc => publicBatch.delete(doc.ref));
            await publicBatch.commit();
            console.log(`Public ideas deleted for ${userId}`);
        }

        // 7. Remove user from group members (optional cleanup)
        const groupMembersSnap = await db.collectionGroup("members").where("userId", "==", userId).get();
        if (groupMembersSnap.size > 0) {
            const memberBatch = db.batch();
            console.log(`Found ${groupMembersSnap.size} group memberships to remove`);
            groupMembersSnap.forEach(doc => memberBatch.delete(doc.ref));
            await memberBatch.commit();
            console.log(`Group memberships removed for ${userId}`);
        }

        console.log(`Firestore cleanup complete for user ${userId}`);
    } catch (error) {
        console.error(`Error cleaning up Firestore for user ${userId}:`, error);
    }
});
