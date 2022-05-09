var toggle_theme = document.getElementById('toggle_theme');
toggle_theme.href = 'javascript:void(0);';

toggle_theme.addEventListener('click', function () {
  var dark_mode = document.body.classList.contains("light-theme");

  var url = '/toggle_theme?redirect=false';
  var xhr = new XMLHttpRequest();
  xhr.responseType = 'json';
  xhr.timeout = 10000;
  xhr.open('GET', url, true);

  set_mode(dark_mode);
  window.localStorage.setItem('dark_mode', dark_mode ? 'dark' : 'light');

  xhr.send();
});

window.addEventListener('storage', function (e) {
  if (e.key === 'dark_mode') {
    update_mode(e.newValue);
  }
});

window.addEventListener('DOMContentLoaded', function () {
  window.localStorage.setItem('dark_mode', document.getElementById('dark_mode_pref').textContent);
  update_mode(window.localStorage.dark_mode);
});

var darkScheme = window.matchMedia('(prefers-color-scheme: dark)');
var lightScheme = window.matchMedia('(prefers-color-scheme: light)');

darkScheme.addListener(scheme_switch);
lightScheme.addListener(scheme_switch);

function scheme_switch (e) {
  if (localStorage.getItem('dark_mode')) {
    return;
  }
  if (e.matches) {
    if (e.media.includes("dark")) {
      set_mode(true);
    } else if (e.media.includes("light")) {
      set_mode(false);
    }
  }
}

function set_mode (bool) {
  if (bool) {
    toggle_theme.children[0].setAttribute('class', 'icon ion-ios-sunny');
    document.body.classList.remove('no-theme');
    document.body.classList.remove('light-theme');
    document.body.classList.add('dark-theme');
  } else {
    toggle_theme.children[0].setAttribute('class', 'icon ion-ios-moon');
    document.body.classList.remove('no-theme');
    document.body.classList.remove('dark-theme');
    document.body.classList.add('light-theme');
  }
}

function update_mode (mode) {
  if (mode === 'true' || mode === 'dark') {
    set_mode(true);
  } else if (mode === 'false' || mode === 'light') {
    set_mode(false);
  } else if (document.getElementById('dark_mode_pref').textContent === '' && window.matchMedia('(prefers-color-scheme: dark)').matches) {
    set_mode(true);
  }
}
