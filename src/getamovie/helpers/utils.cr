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

def make_host_url(kemal_config)
  ssl = CONFIG.https_only || kemal_config.ssl
  port = CONFIG.external_port || kemal_config.port

  if ssl
    scheme = "https://"
  else
    scheme = "http://"
  end

  if port != 80 && port != 443
    port = ":#{port}"
  else
    port = ""
    end

  if !CONFIG.domain
    return ""
  end

  host = CONFIG.domain.not_nil!.lchop(".")

  return "#{scheme}#{host}#{port}"
end

def make_client(url : URI)
  client = HTTP::Client.new(url, OpenSSL::SSL::Context::Client.insecure)
  client.read_timeout = 10.seconds
  client.connect_timeout = 10.seconds

  return client
end

def make_client(url : URI, &block)
  client = make_client(url)
  begin
    yield client
  ensure
    client.close
  end
end

def arg_array(array, start = 1)
  if array.size == 0
    args = "NULL"
  else
    args = [] of String
    (start..array.size + start - 1).each { |i| args << "($#{i})" }
    args = args.join(",")
  end

  return args
end

def decode_length_seconds(string)
  length_seconds = string.gsub(/[^0-9:]/, "").split(":").map &.to_i
  length_seconds = [0] * (3 - length_seconds.size) + length_seconds
  length_seconds = Time::Span.new hours: length_seconds[0], minutes: length_seconds[1], seconds: length_seconds[2]
  length_seconds = length_seconds.total_seconds.to_i

  return length_seconds
end

def recode_length_seconds(time)
  if time <= 0
    return ""
  else
    time = time.seconds
    text = "#{time.minutes.to_s.rjust(2, '0')}m"

    if time.total_hours.to_i > 0
      text = "#{time.total_hours.to_i.to_s.rjust(2, '0')}h #{text}"
    end

    text = text.lchop('0')

    return text
  end
end

def decode_time(string)
  time = string.try &.to_f?

  if !time
    hours = /(?<hours>\d+)h/.match(string).try &.["hours"].try &.to_f
    hours ||= 0

    minutes = /(?<minutes>\d+)m(?!s)/.match(string).try &.["minutes"].try &.to_f
    minutes ||= 0

    seconds = /(?<seconds>\d+)s/.match(string).try &.["seconds"].try &.to_f
    seconds ||= 0

    millis = /(?<millis>\d+)ms/.match(string).try &.["millis"].try &.to_f
    millis ||= 0

    time = hours * 3600 + minutes * 60 + seconds + millis // 1000
  end

  return time
end

def decode_date(string : String)
  if string.match(/^\d{4}/)
    Time.utc(string.to_i, 1, 1)
  end

  begin
    return Time.parse(string, "%b, %-d, %Y", Time::Location.local)
  rescue ex
  end

  case string
  when "today"
    return Time.utc
  when "yesterday"
    return Time.utc - 1.day
  else nil
  end

  date = string.split(" ")[-3, 3]
  delta = date[0].to_i

  case date[1]
  when .includes? "second"
    delta = delta.seconds
  when .includes? "minute"
    delta = delta.minutes
  when .includes? "hour"
    delta = delta.hours
  when .includes? "day"
    delta = delta.days
  when .includes? "week"
    delta = delta.weeks
  when .includes? "month"
    delta = delta.months
  when .includes? "year"
    delta = delta.years
  else
    raise "Could not parse #{string}"
  end

  return Time.utc - delta
end

def recode_date(time : Time, locale)
  span = Time.utc - time

  if span.total_days > 365.0
    span = t(locale, "`x` years", (span.total_days.to_i // 365).to_s)
  elsif span.total_days > 30.0
    span = t(locale, "`x` months", (span.total_days.to_i // 30).to_s)
  elsif span.total_days > 7.0
    span = t(locale, "`x` weeks", (span.total_days.to_i // 7).to_s)
  elsif span.total_hours > 24.0
    span = t(locale, "`x` days", (span.total_days.to_i).to_s)
  elsif span.total_minutes > 60.0
    span = t(locale, "`x` hours", (span.total_hours.to_i).to_s)
  elsif span.total_seconds > 60.0
    span = t(locale, "`x` minutes", (span.total_minutes.to_i).to_s)
  else
    span = t(locale, "`x` seconds", (span.total_seconds.to_i).to_s)
  end

  return span
end

def number_with_separator(number)
  number.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
end

def short_text_to_number(number)
  case short_text
  when .ends_with? "M"
    number = short_text.rstrip(" mM").to_f
    number *= 1000000
  when .ends_with? "K"
    number = short_text.rstrip(" kK").to_f
    number *= 1000
  else
    number = short_text.rstrip(" ")
  end

  number = number.to_i

  return number
end

def number_to_short_text(number)
  seperated = number_with_separator(number).gsub(",", ".").split("")
  text = seperated.first(2).join

  if seperated[2]? && seperated[2] != "."
    text += seperated[2]
  end

  text = text.rchop(".0")

  if number // 1_000_000_000 != 0
    text += "B"
  elsif number // 1_000_000_000 != 0
    text += "M"
  elsif number // 1000 != 0
    text += "K"
  end

  text
end

def get_referer(env, fallback = "/", unroll = true)
  referer = env.params.query["referer"]?
  referer ||= env.request.headers["referer"]?
  referer ||= fallback

  referer = URI.parse(referer)

  if unroll
    loop do
      if referer.query
	params = HTTP::Params.parse(referer.query.not_nil!)
	if params["referer"]?
	  referer = URI.parse(URI.decode_www_form(params["referer"]))
	else
	  break
	end
      else
	break
      end
    end
  end

  referer = referer.request_target
  referer = "/" + referer.gsub(/[^\/?@&%=\-_.0-9a-zA-Z]/, "").lstrip("/\\")

  if referer == env.request.path
    referer = fallback
  end

  return referer
end

def convert_theme(theme)
  case theme
  when "true"
    "dark"
  when "false"
    "light"
  when "", nil
    nil
  else
    theme
  end
end

def html_to_content(description_html : String)
  description = description_html.gsub(/(<br>)|(<br\/>)/, {
    "<br>":  "\n",
    "<br/>": "\n",
  })

  if !description.empty?
    description = XML.parse_html(description).content.strip("\n ")
  end

  return description
end

def get_avg_color(image)
  if File.exists? "art/#{image}.json" 
      color = JSON.parse(File.read("art/#{image}.json")).try &.["color"].try &.as_s
  else
    io = IO::Memory.new

    command = "./../contrib/magick/magick convert http://127.0.0.1:#{Kemal.config.port}/images#{image} -resize 25% -colors 5 -unique-colors txt:- | tail -n +2 | awk '{ print $3 }'"
    Process.run(command, shell: true, output: io)

    io.close

    color = io.to_s.split("\n")[0].strip

    result = JSON.build do |json|
      json.object do
	json.field "file", image
	json.field "color", color
      end
    end

    File.write("art/#{image}.json", result.to_s)
  end

  return color
end
