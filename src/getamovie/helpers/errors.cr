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

class InfoException < Exception
end

macro error_template(*args)
  error_template_helper(env, {{*args}})
end

def error_template_helper(env : HTTP::Server::Context, status_code : Int32, exception : Exception)
  if exception.is_a?(InfoException)
    return error_template_helper(env, status_code, exception.message || "")
  end

  env.response.content_type = "text/html"
  env.response.status_code = status_code

  details = %(Title: `#{exception.message} (#{exception.class})`)
  details += %(\nDate: `#{Time::Format::ISO_8601_DATE_TIME.format(Time.utc)}`)
  details += %(\nRoute: `#{env.request.resource}`)
  details += %(\n<details>)
  details += %(\n<summary>Backtrace</summary>)
  details += %(\n<p>)
  details += %(\n   \n```\n)
  details += exception.inspect_with_backtrace.strip
  details += %(\n```)
  details += %(\n</p>)
  details += %(\n</details>)
  error_message = <<-END_HTML
    Oops! Looks like something broke :( Please send the following text to the administrator:
    <pre style="padding: 20px; background: rgba(0, 0, 0, 0.12345);">#{details}</pre>
  END_HTML

  return templated "error"
end

def error_template_helper(env : HTTP::Server::Context, status_code : Int32, error_message : String)
  env.response.content_type = "text/html"
  env.response.status_code = status_code

  return templated "error"
end

macro error_json(*args)
  error_json_helper(env, {{*args}})
end

def error_json_helper(env : HTTP::Server::Context, status_code : Int32, exception : Exception, additional_fields : Hash(String, Object) | Nil)
  if exception.is_a?(InfoException)
    return error_json_helper(env, status_code, exception.message || "", additional_fields)
  end

  env.response.content_type = "application/json"
  env.response.status_code = status_code

  error_message = {"error" => exception.message, "errorBacktrace" => exception.inspect_with_backtrace}

  if additional_fields
    error_message = error_message.merge(additional_fields)
  end

  return error_message.to_json
end

def error_json_helper(env : HTTP::Server::Context, status_code : Int32, exception : Exception)
  return error_json_helper(env, status_code, exception, nil)
end

def error_json_helper(env : HTTP::Server::Context, status_code : Int32, message : String, additional_fields : Hash(String, Object) | Nil)
  env.response.content_type = "application/json"
  env.response.status_code = status_code

  error_message = {"error" => message}

  if additional_fields
    error_message = error_message.merge(additional_fields)
  end

  return error_message.to_json
end

def error_json_helper(env : HTTP::Server::Context, status_code : Int32, error_message : String)
  error_json_helper(env, status_code, error_message, nil)
end
