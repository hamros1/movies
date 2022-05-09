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

class GetAMovie::Jobs::PullContentInfoJob < GetAMovie::Jobs::BaseJob
  private getter db : DB::Database

  def initialize(@db)
  end

  def begin
    loop do
      tmdb = db.query_all("SELECT tmdb_id FROM movies ORDER BY random()", as: String)
      tmdb.each do |id|
        begin
          refresh_film_data id
        rescue ex
	  puts ex.message
        end
      end

      tmdb = db.query_all("SELECT tmdb_id FROM tv ORDER BY random()", as: String)
      tmdb.each do |id|
        begin
	  refresh_series_data id
        rescue ex
	  puts ex.message
        end
      end

      sleep 180.minutes
    end
  end
end
