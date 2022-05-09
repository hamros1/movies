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

class GetAMovie::Jobs::NotificationJob < GetAMovie::Jobs::BaseJob
  private getter connection_channel : Channel({Bool, Channel(PQ::Notification)})
  private getter pg_url : URI

  def initialize(@connection_channel, @pg_url)
  end

  def begin
    connections = [] of Channel(PQ::Notification)
    PG.connect_listen(pg_url, "notifications") { |event| connections.each(&.send(event)) }

    loop do
      action, connection = connection_channel.receive

      case action
      when true
        connections << connection
      when false
        connections.delete(connection)
      end
    end
  end
end
