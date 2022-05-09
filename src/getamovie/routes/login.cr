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

class GetAMovie::Routes::Login < GetAMovie::Routes::BaseRoute
  def login_page(env)
    locale = LANGS[env.get("preferences").as(Preferences).locale]?

    user = env.get? "user"

    return env.redirect "/" if user

    referer = get_referer(env, "/")

    email = nil
    password = nil

    templated "login"
  end

  def login(env)
    locale = LANGS[env.get("preferences").as(Preferences).locale]

    referer = get_referer(env, "browse")

    email = env.params.body["email"]?.try &.downcase.byte_slice(0, 254)

    password = env.params.body["password"]?

    if !email
      return error_template(401, "Email is a required field")
    end

    if !password
      return error_template(401, "Password is a required field")
    end

    user = PG_DB.query_one?("SELECT * FROM users WHERE email = $1", email, as: User)

    if user
      if Crypto::Bcrypt::Password.new(user.password.not_nil!).verify(password.byte_slice(0, 55))
	sid = Base64.urlsafe_encode(Random::Secure.random_bytes(32))
	PG_DB.exec("INSERT INTO session_ids VALUES ($1, $2, $3)", sid, email, Time.utc)

	if Kemal.config.ssl || CONFIG.https_only
	  secure = true
	else
	  secure = false
	end

	if CONFIG.domain
	  env.response.cookies["SID"] = HTTP::Cookie.new(name: "SID", domain: "#{CONFIG.domain}", value: sid, expires: Time.utc + 2.years, secure: secure, http_only: true)
	else
	  env.response.cookies["SID"] = HTTP::Cookie.new(name: "SID", value: sid, expires: Time.utc + 2.years, secure: secure, http_only: true)
	end
      else
	return error_template(401, "Wrong username or password")
      end

      if env.request.cookies["PREFS"]?
	cookie = env.request.cookies["PREFS"]
	cookie.expires = Time.utc(1990, 1, 1)
	env.response.cookies << cookie
      end
    else
      if password.empty?
	return error_template(401, "Password cannot be empty")
      end

      if password.bytesize > 55
	return error_template(400, "Password cannot be longer than 55 characters")
      end

      password = password.byte_slice(0, 55)

      sid = Base64.urlsafe_encode(Random::Secure.random_bytes(32))
      user, sid = create_user(sid, email, password)

      user_array = user.to_a
      user_array[4] = user_array[4].to_json

      args = arg_array(user_array)

      PG_DB.exec("INSERT INTO users VALUES (#{args})", args: user_array)
      PG_DB.exec("INSERT INTO session_ids VALUES ($1, $2, $3)", sid, email, Time.utc)

      if Kemal.config.ssl || CONFIG.https_only
	secure = true
      else
	secure = false
      end

      if CONFIG.domain
	env.response.cookies["SID"] = HTTP::Cookie.new(name: "SID", domain: "#{CONFIG.domain}", value: sid, expires: Time.utc + 2.years, secure: secure, http_only: true)
      else
	env.response.cookies["SID"] = HTTP::Cookie.new(name: "SID", value: sid, expires: Time.utc + 2.years, secure: secure, http_only: true)
      end

      if env.request.cookies["PREFS"]?
	preferences = env.get("preferences").as(Preferences)
	PG_DB.exec("UPDATE users SET preferences = $1 WHERE email = $2", preferences.to_json, user.email)
	
	cookie = env.request.cookies["PREFS"]
	cookie.expires = Time.utc(1990, 1, 1)
	env.request.cookies << cookie
      end
    end

    env.redirect referer
  end

  def signout(env)
    locale = LANGS[env.get("preferences").as(Preferences).locale]?

    user = env.get? "user"
    sid = env.get? "sid"
    referer = get_referer(env)

    if !user
      return env.redirect referer
    end

    user = user.as(User)
    sid = sid.as(String)
    token = env.params.body["csrf_token"]?

    begin
      validate_request(token, sid, env.request, HMAC_KEY, PG_DB, locale)
    rescue ex
      return error_template(400, ex)
    end

    env.request.cookies.each do |cookie|
      cookie.expires = Time.utc(1990, 1, 1)
      env.response.cookies << cookie
    end

    env.redirect referer
  end
end
