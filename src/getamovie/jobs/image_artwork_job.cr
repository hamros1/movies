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

class GetAMovie::Jobs::ImageArtworkJob < GetAMovie::Jobs::BaseJob
  private getter db : DB::Database

  def initialize(@db)
  end

  def begin
    loop do
      images = db.query_all("SELECT posters FROM movies ORDER by tmdb_id DESC", as: Array(String) | Nil)
      begin
        image = images[0].try &.to_s
        get_avg_color(image)
      rescue
      end
      #      images.try &.to_a.each do |imagez|
      #        begin
      #	  imagez.try &.to_a.each do |image|
      #            get_avg_color(image)
      #	  end
      #        rescue
      #        end
    end

    images = db.query_all("SELECT backdrops FROM movies ORDER by tmdb_id DESC", as: Array(String) | Nil)
    begin
      image = images[0].try &.to_s
      get_avg_color(image)
    rescue
    end
    #      images.try &.to_a.each do |imagez|
    #        begin
    #	  imagez.try &.to_a.each do |image|
    #            get_avg_color(image)
    #	  end
    #        rescue
    #        end
    #      end

    images = db.query_all("SELECT posters FROM tv ORDER by tmdb_id DESC", as: Array(String) | Nil)
    begin
      image = images[0].try &.to_s
      get_avg_color(image)
    rescue
    end
    #      images.try &.to_a.each do |imagez|
    #        begin
    #	  imagez.try &.to_a.each do |image|
    #            get_avg_color(image)
    #	  end
    #        rescue
    #        end
    #      end

    images = db.query_all("SELECT backdrops FROM tv ORDER by tmdb_id DESC", as: Array(String) | Nil)
    begin
      image = images[0].try &.to_s
      get_avg_color(image)
    rescue
    end
    #      images.try &.to_a.each do |imagez|
    #        begin
    #	  imagez.try &.to_a.each do |image|
    #            get_avg_color(image)
    #	  end
    #        rescue
    #        end
    #      end
    #    end

    sleep 3000.seconds
  end
end
