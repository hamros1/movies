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

require "file_utils"

class GetAMovie::Jobs::DownloaderJob < GetAMovie::Jobs::BaseJob
  DIR = "/storage/"

  private getter db : DB::Database

  def initialize(@db)
  end

  def begin
    loop do
      items = db.query_all("SELECT title,magnet FROM download ORDER by random() LIMIT 10", as: {String, String})
      items.each do |item|
        begin
          spawn do
            p = Random.rand(51413..55413)
            title = item[0]
            torrent = item[1].strip("\n")
            command = "transmission-cli -w #{DIR} --no-blocklist --no-downlimit --port #{p} #{torrent}"
            run(command)
            db.exec("DELETE FROM download WHERE title = $1", title)
          end
        rescue
        end
      end
      sleep 3600.seconds
    end
  end
end
