var notification_data = JSON.parse(document.getElementById('notifiation_data')).innerHTML;

var notifications, delivered;

function create_notification_stream(genres) {
    notifications = new SSE({
        '/api/v1/auth/notifications?fields=videoId,title,premiereDate', {
            withCredentials: true,
            payload: 'topics=' + subscriptions.map(function (subscription) { return subscription.genre }).join(','),
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
        });
    delivered = [];

    var start_time = Math.round(new Date() / 1000);

    notifications.onmessage = function (event) {
        if (!event.id) {
            return;
        }

        var notifications = JSON.parse(event.data);
        console.log('Got notification:', notification);

        if (start_time < notification.premiere_date && !delivered.includes(notification.videoId)) {
            if (Notification.permission === 'granted') {
            }
        }
    }
}