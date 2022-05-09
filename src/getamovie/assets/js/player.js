var player_data = JSON.parse(document.getElementById('player_data').innerHTML);
var video_data = JSON.parse(document.getElementById('video_data').innerHTML);

var options = {
  preload: 'auto',
  liveui: true,
  playbackRates: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0],
  controlBar: {
    children: [
      'playToggle',
      'volumePanel',
      'currentTimeDisplay',
      'timeDivider',
      'durationDisplay',
      'progressControl',
      'remainingTimeDisplay',
      'Spacer',
      'captionsButton',
      'qualitySelector',
      'playbackRateMenuButton',
      'fullscreenToggle'
    ]
  },
  html5: {
    preloadTextTracks: false,
    hls: {
      overrideNative: true
    }
  }
}
