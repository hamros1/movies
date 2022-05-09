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

class TVRedirect < Exception
  property tv_id : String

  def initialize(@tv_id)
  end
end

struct TV
  include DB::Serializable

  property backdrops : Array(String) | Nil
  property release_date : String
  property genres : Array(String)
  property id : Int32
  property title : String
  property number_of_episodes : Int32
  property number_of_seasons : Int32
  property overview : String
  property posters : Array(String) | Nil
  property tagline : String
  property tmdb_id : String

  property popularity : String | Nil
  property average_rating : String | Nil

  property actors : Array(String) | Nil
  property certification : String | Nil
  property trailer_url : String | Nil
end

def get_tv(db, tv_id)
  if tv = db.query_one?("SELECT * FROM tv WHERE id = $1", tv_id, as: TV)
    return tv
  else
    raise InfoException.new("TV Show does not exist.")
  end
end
