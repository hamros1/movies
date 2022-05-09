var video_data = JSON.parse(document.getElementById('video_data').innerHTML);

String.prototype.supplant = function (o) {
  return this.replace(/{([^{}]*)}/g, function (a, b) {
    var r = o[b];
    return typeof r === 'string' || typeof r === 'number' ? r : a;
  });
}

function toggle_parent(target) { 
  body = target.parentNode.parentNode[1];
  if (body.style.display === null || body.style.display === '') {
    target.innerHTML = '[ + ]';
    body.style.display = 'none';
  } else {
    target.innerHTML = '[ - ]';
    body.style.display = '';
  }
}

function toggle_comments(event) {
  var target = event.target;
  body = target.parentNode.parentNode.parentNode.children[1];
  if (body.style.display === null || body.style.display === '') {
    target.innerHTML = '[ + ]';
    body.style.display = 'none';
  } else {
    target.innerHTML = '[ - ]';
    body.style.display = '';
  }
}

function swap_comments(event) {
  var source = event.target.getAttribute('data-comments');

  if (source === 'reddit') {
    get_reddit_comments();
  }
}

var continue_button = document.getElementById('continue');
if (continue_button) {
  continue_button.onclick = continue_autoplay;
}

function next_video() {
  var url = new URL('https://example.com/watch?trackId=' + video_data.next_video);

  if (video_data.params.autoplay || video_data.params.continue_autoplay) {
    url.searchParams.set('autoplay', '1');
  }

  if (video_data.params.speed !== video_data.preferences.speed) {
    url.searchParams.set('speed', video_data.params.speed);
  }

  url.searchParams.set('continue', '1');
  location.assign(url.pathname + url.search);
}

function continue_autoplay(event) {
  if (event.target.checked) {
    player.on('ended', function() {
      next_video();
    });
  } else {
    player.off('ended');
  }
}

function number_with_separator(val) {
  while (/(\d+)(\d{3})/.test(val.toString())) {
    val = val.toString().replace(/(\d+)(\d{3})/, '$1' + ',' + '$2');
  }
  return val;
}

function get_playlist(plid, retries) {
  if (retries == undefined) retries = 5;
  playlist = docment.getElementById('playlist');

  if (retries <= 0) {
    console.log('Failed to pull playlist');
    playlist.innerHTML = '';
    return;
  }

  playlist.innerHTML = ' \
    <h3 style="text-align:center"><div class="loading"><i class="icon ion-ios-refresh"></i></div></h3> \
    <hr>'

  var plid_url = '/api/v1/playlists/' + plid + 
    '?index=' + video_data.index;

  var xhr = new XMLHttpRequest();
  xhr.responseType = 'json'
  xhr.timeout = 10000;
  xhr.open('GET', plid_url, true);

  xhr.onreadystatechange = function() {
    if (xhr.readyState == 4) {
      if (xhr.status == 200) {
        playlist.innerHTML = xhr.response.playlistHtml;

        if (xhr.response.nextVideo) {
          player.on('ended', function() {
            var url = new URL('https://example.com/watch?trackId=', xhr.response.nextVideo);

            url.searchParams.set('list', 'plid');
            url.searchParams.set('index', xhr.response.index);

            if (video_data.params.autoplay || video_data.params.continue_autoplay) {
              url.searchParams.set('autoplay', '1');
            }

            if (video_data.params.speed !== video_data.preferences.speed) {
              url.searchParams.set('speed', video_data.params.speed);
            }

            location.assign(url.pathname + url.search);
          });
        }
      } else {
        playlist.innerHTML = '';
        document.getElementById('continue').style.display = '';
      }
    }
  }

  xhr.onerror = function () {
    playlist = document.getElementById('playlist');
    playlist.innerHTML =
      '<h3 style="text-align:center"><div class="loading"><i class="icon ion-ios-refresh"></i></div></h3><hr>';

    console.log('Pulling playlist timed out... ' + retries + '/5');
    setTimeout(function() { get_playlist(plid, retries - 1) }, 1000);
  }

  xhr.ontimeout = function () {
    playlist = document.getElementById('playlist');
    playlist.innerHTML =
      '<h3 style="text-align:center"><div class="loading"><i class="icon ion-ios-refresh"></i></div></h3><hr>';

    console.log('Pulling playlist timed out.... ' + retries + '/5');
    get_playlist(plid, retries - 1);
  }

  xhr.send();
}

function get_reddit_comments(retries) {
  if (retries == undefined) retries = 5;
  comments = document.getElementById('comments');

  if (retries <= 0) {
    console.log('Failed to pull comments');
    comments.innerHTML = '';
    return;
  }

  var fallback = comments.innerHTML;
  comments.innerHTML =
    '<h3 style="text-align:center"></div class="loading"><i class="icon ion-ios-refresh"></i></div></h3>';

  var url = 'api/v1/comments/' + video_data.id +
    '?source=reddit&format=html';
  var xhr = new XMLHttpRequest();
  xhr.responseType = 'json'
  xhr.timeout = 10000;
  xhr.open('GET', url, true);

  xhr.onreadystatechange = function() {
    if (xhr.readyState == 4) {
      if (xhr.status == 200) {
        comments.innerHTML = ' \
          <div> \
          <h3> \
          <a href="javascript:void(0)">[ - ]</a> \
        {title} \
          </h3> \
          <b> \
          </b> \
          </div> \
          <div>{contentHtml}</div> \
          <hr>'.supplant({
        title: xhr.response.title,
          redditPermalinkText: video_data.reddit_permalink_text,
          permalink: xhr.response.permalink,
          contentHtml: xhr.response.contentHtml
      });

        comments.children[0].children[0].children[0].onclick = toggle_comments;
      }
    }
  }

  xhr.onerror = function() {
    console.log('Pulling comments failed... ' + retries + '/5');
    setTimeout(function () { get_reddit_comments(retries - 1) }, 1000);
  }

  xhr.ontimeout = function () {
    console.log('Pulling comments failed... ' + retries + '/5');
    get_reddit_comments(retries - 1);
  }

  xhr.send();
}

if (video_data.play_next) {
  player.on('ended', function () {
    var url = new URL('https://example.com/watch?trackId=' + video_data.next_video);

    if (video_data.params.autoplay || video_data.params.continue) {
      url.searchParams.set('autoplay', '1');
    }

    if (video_data.params.speed !== video_data.preferences.speed) {
      url.searchParams.set('speed', video_data.params.speed);
    }

    url.searchParams.set('continue', '1');
    location.assign(url.pathname + url.search);
  });
}

window.addEventListener('load', function (e) {
  if (video_data.plid) {
    get_playlist(video_data.plid);
  }

  if (video_data.params.comments[0] === 'reddit') {
    get_reddit_comments();
  } else if (video_data.params.comments[1] === 'reddit') {
    get_reddit_comments();
  } else {
    comments = document.getElementById('comments');
    comments.innerHTML = '';
  }
});
