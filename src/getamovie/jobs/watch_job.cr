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

class GetAMovie::Jobs::WatchJob < GetAMovie::Jobs::BaseJob
  private getter db : DB::Database

  def initialize(@db)
  end

  def begin
    loop do
      output = IO::Memory.new
      process = Process.new("ls -d /storage/*", shell: true, output: output, error: output)
      process.wait
      output = output.to_s

      file_arr = output.split("\n")
      file_arr.each do |file|
        begin
          if file.includes? "Encoding"
            next
          end

          files = Dir.entries("#{file}")
          files = files.map { |f| "#{file}/#{f}" }.try &.to_a

          all_files = [] of String
          files.each do |dir_file|
            if (dir_file.ends_with?(".mp4") || dir_file.ends_with?(".mkv"))
              all_files << dir_file
            end
          end

          all_files.each do |f|
            begin
              command = "mv \"#{f}\" /storage/Encoding/"
              run command
            rescue ex
              next
            end
          end
        rescue ex
          next
        end
      end
    end
  end
end
