const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ══════════════════════════════════════════════════════
// FUNCTION 1: Daily mood reminder at 5 PM Malaysia time
// ══════════════════════════════════════════════════════
exports.dailyMoodReminder = functions.pubsub
  .schedule("0 9 * * *")
  .timeZone("Asia/Kuala_Lumpur")
  .onRun(async (context) => {
    const today = new Date().toISOString().substring(0, 10);
    const studentsSnapshot = await db.collection("students").get();

    for (const studentDoc of studentsSnapshot.docs) {
      const studId = studentDoc.id;
      const studentData = studentDoc.data();
      const fcmToken = studentData.fcmToken;
      if (!fcmToken) continue;

      const moodQuery = await db
        .collection("moodLogs")
        .where("stud_id", "==", studId)
        .where("log_date", "==", today)
        .limit(1)
        .get();

      if (moodQuery.empty) {
        try {
          await messaging.send({
            token: fcmToken,
            notification: {
              title: "MindEase 💙",
              body: "Reflect on your day — how are you feeling today?",
            },
            android: {
              notification: { channelId: "mindease_channel", priority: "high" },
            },
          });
        } catch (e) {
          console.error(`Failed to send reminder to ${studId}: ${e}`);
        }
      }
    }
    return null;
  });

// ══════════════════════════════════════════════════════
// FUNCTION 2: Alert PA if student hasn't logged for 3+ days
// ══════════════════════════════════════════════════════
exports.alertPAMissingMood = functions.pubsub
  .schedule("0 12 * * *")
  .timeZone("Asia/Kuala_Lumpur")
  .onRun(async (context) => {
    const today = new Date();
    const studentsSnapshot = await db.collection("students").get();

    for (const studentDoc of studentsSnapshot.docs) {
      const studId = studentDoc.id;
      const studentData = studentDoc.data();
      const paName = studentData.paName;
      if (!paName) continue;

      const moodQuery = await db
        .collection("moodLogs")
        .where("stud_id", "==", studId)
        .orderBy("log_date", "descending")
        .limit(1)
        .get();

      let daysMissing = 0;
      if (moodQuery.empty) {
        daysMissing = 3;
      } else {
        const lastLogDate = new Date(moodQuery.docs[0].data().log_date);
        daysMissing = Math.floor((today - lastLogDate) / (1000 * 60 * 60 * 24));
      }

      if (daysMissing >= 3) {
        const paQuery = await db
          .collection("personalAdvisor")
          .where("fullName", "==", paName)
          .limit(1)
          .get();

        if (!paQuery.empty) {
          const paToken = paQuery.docs[0].data().fcmToken;
          if (paToken) {
            try {
              await messaging.send({
                token: paToken,
                notification: {
                  title: "Student Alert ⚠️",
                  body: `${studentData.fullName} hasn't logged their mood for ${daysMissing} days`,
                },
                android: {
                  notification: { channelId: "mindease_channel", priority: "high" },
                },
              });
            } catch (e) {
              console.error(`Failed to send PA alert: ${e}`);
            }
          }
        }
      }
    }
    return null;
  });

// ══════════════════════════════════════════════════════
// FUNCTION 3: Notify counsellor when PA submits referral
// Triggers when a new referral document is created
// ══════════════════════════════════════════════════════
exports.notifyCounsellorOnReferral = functions.firestore
  .document("referrals/{referralId}")
  .onCreate(async (snap, context) => {
    const referral = snap.data();
    const counsellorId = referral.counsellor_id;
    const studId = referral.stud_id;

    // Get student name
    const studentDoc = await db.collection("students").doc(studId).get();
    const studentName = studentDoc.exists
      ? studentDoc.data().fullName
      : "A student";

    // Get PA name
    let paName = "Personal Advisor";
    if (referral.pa_id) {
      const paDoc = await db.collection("personalAdvisor").doc(referral.pa_id).get();
      if (paDoc.exists) paName = paDoc.data().fullName;
    }

    // Get counsellor FCM token
    const counsellorDoc = await db.collection("counsellors").doc(counsellorId).get();
    if (!counsellorDoc.exists) return null;

    const fcmToken = counsellorDoc.data().fcmToken;
    if (!fcmToken) {
      console.log(`No FCM token for counsellor ${counsellorId}`);
      return null;
    }

    try {
      await messaging.send({
        token: fcmToken,
        notification: {
          title: "New Referral Request 📋",
          body: `${paName} has referred ${studentName} to you`,
        },
        android: {
          notification: { channelId: "mindease_channel", priority: "high" },
        },
        data: {
          type: "new_referral",
          referral_id: context.params.referralId,
        },
      });
      console.log(`Referral notification sent to counsellor ${counsellorId}`);
    } catch (e) {
      console.error(`Failed to notify counsellor: ${e}`);
    }

    return null;
  });

// ══════════════════════════════════════════════════════
// FUNCTION 4: Notify PA when counsellor accepts/rejects referral
// Triggers when referral status changes
// ══════════════════════════════════════════════════════
exports.notifyPAOnReferralUpdate = functions.firestore
  .document("referrals/{referralId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    // Only trigger on status change
    if (before.status === after.status) return null;

    const newStatus = after.status;
    if (newStatus !== "accepted" && newStatus !== "rejected") return null;

    const studId = after.stud_id;
    const paId = after.pa_id;

    if (!paId) return null;

    // Get student name
    const studentDoc = await db.collection("students").doc(studId).get();
    const studentName = studentDoc.exists
      ? studentDoc.data().fullName
      : "Student";

    // Get counsellor name
    const counsellorDoc = await db
      .collection("counsellors")
      .doc(after.counsellor_id)
      .get();
    const counsellorName = counsellorDoc.exists
      ? counsellorDoc.data().fullName
      : "Counsellor";

    // Get PA FCM token
    const paDoc = await db.collection("personalAdvisor").doc(paId).get();
    if (!paDoc.exists) return null;

    const paToken = paDoc.data().fcmToken;
    if (!paToken) return null;

    const isAccepted = newStatus === "accepted";

    try {
      await messaging.send({
        token: paToken,
        notification: {
          title: isAccepted ? "Referral Accepted ✅" : "Referral Rejected ❌",
          body: isAccepted
            ? `${studentName} is now under ${counsellorName}`
            : `${counsellorName} rejected the referral for ${studentName}`,
        },
        android: {
          notification: { channelId: "mindease_channel", priority: "high" },
        },
        data: {
          type: isAccepted ? "referral_accepted" : "referral_rejected",
          referral_id: context.params.referralId,
        },
      });
      console.log(`PA notified: referral ${newStatus} for ${studentName}`);
    } catch (e) {
      console.error(`Failed to notify PA: ${e}`);
    }

    return null;
  });

// ══════════════════════════════════════════════════════
// FUNCTION 5: Send FCM from notifications collection
// Handles in-app triggered notifications
// ══════════════════════════════════════════════════════
exports.sendNotification = functions.firestore
  .document("notifications/{notifId}")
  .onCreate(async (snap, context) => {
    const notif = snap.data();
    const token = notif.to_token;
    if (!token) return null;

    try {
      await messaging.send({
        token: token,
        notification: {
          title: notif.title,
          body: notif.body,
        },
        android: {
          notification: { channelId: "mindease_channel", priority: "high" },
        },
      });
      console.log(`Notification sent: ${notif.title}`);
    } catch (e) {
      console.error(`Failed to send notification: ${e}`);
    }

    return null;
  });