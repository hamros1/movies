# This file is a component in the Rosencrantz Entertainment Conglomerate
# Copyright (C) 2021 Hampus Andreas Niklas Rosencrantz

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

class GetAMovie::Routes::PreferencesRoute < GetAMovie::Routes::BaseRoute
  def show(env)
    locale = LANGS[env.get("preferences").as(Preferences).locale]?

    referer = get_referer(env)

    preferences = env.get("preferences").as(Preferences)
  end

  def update(env)
    locale = LANGS[env.get("preferences").as(Preferences).locale]?

    referer = get_referer(env)

    autoplay = env.params.body["autoplay"]?.try &.as(String)
    autoplay ||= "off"
    autoplay = autoplay == "on"

    continue = env.params.body["continue"]?.try &.as(String)
    continue ||= "off"
    continue = continue == "on"

    continue_autoplay = env.params.body["continue_autoplay"]?.try &.as(String)
    continue_autoplay ||= "off"
    continue_autoplay = continue_autoplay == "on"

    proxy = env.params.body["proxy"]?.try &.as(String)
    proxy ||= "off"
    proxy = proxy == "on"

    speed = env.params.body["speed"]?.try &.as(String).to_f32?
    speed ||= CONFIG.default_user_preferences.speed

    quality = env.params.body["quality"]?.try &.as(String)
    quality ||= CONFIG.default_user_preferences.quality

    volume = env.params.body["volume"]?.try &.as(String).to_i?
    volume ||= CONFIG.default_user_preferences.volume

    extend_desc = env.params.body["extend_desc"]?.try &.as(String)
    extend_desc ||= "off"
    extend_desc = extend_desc == "on"

    comments = [] of String
    2.times do |i|
      comments << (env.params.body["comments[#{i}]"]?.try &.as(String) || CONFIG.default_user_preferences.comments[i])
    end

    captions = [] of String
    3.times do |i|
      captions << (env.params.body["captions[#{i}]"]?.try &.as(String) || CONFIG.default_user_preferences.captions[i])
    end

    locale = env.params.body["locale"]?.try &.as(String)
    locale ||= CONFIG.default_user_preferences.locale

    dark_mode = env.params.body["dark_mode"]?.try &.as(String)
    dark_mode ||= CONFIG.default_user_preferences.dark_mode

    max_results = env.params.body["max_results"]?.try &.as(String).to_i?
    max_results ||= CONFIG.default_user_preferences.max_results

    sort = env.params.body["sort"]?.try &.as(String)
    sort ||= CONFIG.default_user_preferences.sort

    unseen_only = env.params.body["unseen_only"]?.try &.as(String)
    unseen_only ||= "off"
    unseen_only = unseen_only == "on"

    preferences = Preferences.from_json({
      autoplay:          autoplay,
      captions:          captions,
      comments:          comments,
      continue:          continue,
      continue_autoplay: continue_autoplay,
      proxy:             proxy,
      dark_mode:         dark_mode,
      locale:            locale,
      max_results:       max_results,
      quality:           quality,
      sort:              sort,
      speed:             speed,
      unseen_only:       unseen_only,
      extend_desc:       extend_desc,
      volume:            volume,
    }.to_json).to_json

    if user = env.get? "user"
      user = user.as(User)
      PG_DB.exec("UPDATE users SET preferences = $1 WHERE email = $2", preferences, user.email)

      if CONFIG.admins.includes? user.email
        captcha_enabled = env.params.body["captcha_enabled"]?.try &.as(String)
        captcha_enabled ||= "off"
        CONFIG.captcha_enabled = captcha_enabled == "on"

        login_enabled = env.params.body["login_enabled"]?.try &.as(String)
        login_enabled ||= "off"
        CONFIG.login_enabled = login_enabled == "on"

        registration_enabled = env.params.body["registration_enabled"]?.try &.as(String)
        registration_enabled ||= "off"
        CONFIG.registration_enabled = registration_enabled == "on"

        File.write("config/config.yml", CONFIG.to_yaml)
      end
    else
      if Kemal.config.ssl || CONFIG.https_only
        secure = true
      else
        secure = false
      end

      if CONFIG.domain
        env.response.cookies["PREFS"] = HTTP::Cookie.new(name: "PREFS", domain: "#{CONFIG.domain}", value: URI.encode_www_form(preferences), expires: Time.utc + 2.years,
          secure: secure, http_only: true)
      else
        env.response.cookies["PREFS"] = HTTP::Cookie.new(name: "PREFS", value: URI.encode_www_form(preferences), expires: Time.utc + 2.years,
          secure: secure, http_only: true)
      end
    end

    env.redirect referer
  end

  def toggle_theme(env)
    locale = LANGS[env.get("preferences").as(Preferences).locale]?

    referer = get_referer(env, unroll: false)

    redirect = env.params.query["redirect"]?
    redirect ||= "true"
    redirect = redirect == "true"

    if user = env.get? "user"
      user = user.as(User)
      preferences = user.preferences

      case preferences.dark_mode
      when "dark"
        preferences.dark_mode = "light"
      else
        preferences.dark_mode = "dark"
      end

      preferences = preferences.to_json

      PG_DB.exec("UPDATE users SET preferences = $1 WHERE email = $2", preferences, user.email)
    else
      preferences = env.get("preferences").as(Preferences)

      case preferences.dark_mode
      when "dark"
        preferences.dark_mode = "light"
      else
        preferences.dark_mode = "dark"
      end

      preferences = preferences.to_json

      if Kemal.config.ssl || CONFIG.https_only
        secure = true
      else
        secure = false
      end

      if CONFIG.domain
        env.response.cookies["PREFS"] = HTTP::Cookie.new(name: "PREFS", "domain": "#{CONFIG.domain}", value: URI.encode_www_form(preferences), expires: Time.utc + 2.years, secure: secure, http_only: true)
      else
        env.response.cookies["PREFS"] = HTTP::Cookie.new(name: "PREFS", value: URI.encode_www_form(preferences), expires: Time.utc + 2.years, secure: secure, http_only: true)
      end
    end

    if redirect
      env.redirect referer
    else
      env.response.content_type = "application/json"
      "{}"
    end
  end
end
