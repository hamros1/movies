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

class GetAMovie::Routes::Api::WatchParty < GetAMovie::Routes::BaseRoute
  def watch_party(socket)
    socket.on_message do |message|
      message = JSON.parse(message)
      channel_id = message["d"]["channel_id"].try &.as_s

      if message["op"] == "CONNECT"
        SOCKETS[socket] = channel_id
        ch = SOCKETS.select { |k, v| v == channel_id }.try &.to_a
        ch.each do |s, c|
          data = JSON.build do |json|
            json.object do
              json.field "op", "CHANNEL_UPDATE"
              json.field "d" do
                json.object do
                  json.field "members" do
                    json.array do
                      ch.each do |m|
                        json.object do
                          json.field "name", "Guest"
                          json.field "image", "https://external-content.duckduckgo.com/iu/?u=http%3A%2F%2Fi167.photobucket.com%2Falbums%2Fu126%2FNeckTiesandTophats%2F3650256.gif&f=1&nofb=1"
                        end
                      end
                    end
                  end
                  if s == ch.try &.map { |k, v| k }.try &.to_a[0]
                    json.field "isOwner", true
                  else
                    json.field "isOwner", false
                  end
                end
              end
            end
          end

          s.send(data)
        end
      end

      # room owner is boss
      if socket != SOCKETS.select { |k, v| v == channel_id }.try &.map { |k, v| k }.try &.to_a[0] && message["op"] != "CHANNEL_CHAT"
        next
      end

      if message["op"] == "PLAYER_PAUSE" || message["op"] == "PLAYER_PLAY" || message["op"] == "PLAYER_SEEK" || message["op"] == "TIME_UPDATE"
        SOCKETS.select { |k, v| v == channel_id }.try &.to_a[1..-1].each do |s, c|
          data = JSON.build do |json|
            json.object do
              json.field "op", message["op"].try &.as_s
              json.field "d" do
                json.object do
                  json.field "currentTime", message["d"]["currentTime"].try &.to_s
                end
              end
            end
          end
          s.send(data)
        end
      elsif message["op"] == "CHANNEL_CHAT"
        SOCKETS.select { |k, v| v == channel_id }.try &.to_a.each do |s, c|
          data = JSON.build do |json|
            json.object do
              json.field "op", message["op"].try &.as_s
              json.field "d" do
                json.object do
                  json.field "author", "Guest"
                  json.field "date", message["d"]["date"].try &.to_s
                  json.field "text", HTML.escape(message["d"]["text"].try &.to_s)
                end
              end
            end
          end
          s.send(data)
        end
      end
    end

    socket.on_close do
      ch = SOCKETS[socket].dup
      SOCKETS.delete(socket)

      ch = SOCKETS.select { |k, v| v == ch }.try &.to_a
      ch.each do |s, c|
        data = JSON.build do |json|
          json.object do
            json.field "op", "CHANNEL_UPDATE"
            json.field "d" do
              json.object do
                json.field "members" do
                  json.array do
                    ch.each do |m|
                      json.object do
                        json.field "name", "Guest"
                        json.field "image", "https://external-content.duckduckgo.com/iu/?u=http%3A%2F%2Fi167.photobucket.com%2Falbums%2Fu126%2FNeckTiesandTophats%2F3650256.gif&f=1&nofb=1"
                      end
                    end
                  end
                end
                if s = ch.try &.map { |k, v| k }.try &.to_a[0]
                  json.field "isOwner", true
                else
                  json.field "isOwner", false
                end
              end
            end
          end
        end

        s.send(data)
      end
    end
  end
end
