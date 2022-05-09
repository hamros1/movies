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

struct Season
  include DB::Serializable

  property _id : Int32
  property air_date : String
  property name : String
  property overview : String
  property id : String
  property poster_path : String
  property season_number : Int32
end

def get_tv_season(db, tv_id, season_number)
  if season = db.query_one?("SELECT * FROM tv_seasons WHERE tv_id = $1 AND season_number = $2", tv_id, season_number, as: Season)
    return season
  else
    return InfoException.new("Season not found.")
  end
end

