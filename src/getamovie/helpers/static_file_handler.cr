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

private def multipart(file, env : HTTP::Server::Context)
  fileb = file.size
  startb = endb = 0

  if match = env.request.headers["Range"].match /bytes=(\d{1,})-(\d{0,})/
    startb = match[1].to_i { 0 } if match.size >= 2
    endb = match[2].to_i { 0 } if match.size >= 3
  end

  endb = fileb - 1 if endb == 0

  if startb < endb < fileb
    content_length = 1 + endb - startb
    env.response.status_code = 206
    env.response.content_length = content_length
    env.response.headers["Accept-Ranges"] = "bytes"
    env.response.headers["Content-Range"] = "bytes #{startb}-#{endb}/#{fileb}"

    if startb > 1024
      skipped = 0
      until (increase_skipped = skipped + 1024) > startb
        file.skip(1024)
        skipped = increase_skipped
      end
      if (skipped_minus_startb = skipped - startb) > 0
        file.skip skipped_minus_startb
      end
    else
      file.skip(startb)
    end

    IO.copy(file, env.response, content_length)
  else
    env.response.content_length = fileb
    env.response.status_code = 200
    IO.copy(file, env.response)
  end
end

private def attachment(env : HTTP::Server::Context, filename : String? = nil, disposition : String? = nil)
  disposition = "attachment" if disposition.nil? && filename
  if disposition && filename
    env.response.headers["Content-Disposition"] = "#{disposition}; filename=\"#{File.basename(filename)}\""
  end
end

def send_file(env : HTTP::Server::Context, file_path : String, data : Slice(UInt8), filestat : File::Info, filename : String? = nil, disposition : String? = nil)
  config = Kemal.config.serve_static
  mime_type = MIME.from_filename(file_path, "application/octet-stream")
  env.response.content_type = mime_type
  env.response.headers["Accept-Ranges"] = "bytes"
  env.response.headers["X-Content-Type-Options"] = "nosniff"
  minsize = 860
  request_headers = env.request.headers
  filesize = data.bytesize
  attachment(env, filename, disposition)

  Kemal.config.static_headers.try(&.call(env.response, file_path, filestat))

  file = IO::Memory.new(data)
  if env.request.method == "GET" && env.request.headers.has_key?("Range")
    return multipart(file, env)
  end

  condition = config.is_a?(Hash) && config["gzip"]? == true && filesize > minsize && Kemal::Utils.zip_types(file_path)
  if condition && request_headers.includes_word?("Accept-Encoding", "gzip")
    env.response.headers["Content-Encoding"] = "gzip"
    Compress::Gzip::Writer.open(env.response) do |deflate|
      IO.copy(file, deflate)
    end
  elsif condition && request_headers.includes_word?("Accept-Encoding", "deflate")
    env.response.headers["Content-Encoding"] = "deflate"
    Compress::Deflate::Writer.open(env.response) do |deflate|
      IO.copy(file, deflate)
    end
  else
    env.response.content_length = filesize
    IO.copy(file, env.response)
  end

  return
end

module Kemal
  class StaticFileHandler < HTTP::StaticFileHandler
    CACHE_LIMIT = 5_000_000 # 5MB
    @cached_files = {} of String => {data: Bytes, filestat: File::Info}

    def call(context : HTTP::Server::Context)
      return call_next(context) if context.request.path.not_nil! == "/"

      case context.request.method
      when "GET", "HEAD"
      else
        if @fallthrough
          call_next(context)
        else
          context.response.status_code = 405
          context.response.headers.add("Allow", "GET, HEAD")
        end
        return
      end

      config = Kemal.config.serve_static
      original_path = context.request.path.not_nil!
      request_path = URI.decode_www_form(original_path)

      if request_path.includes? '\0'
        context.response.status_code = 400
        return
      end

      expanded_path = File.expand_path(request_path, "/")
      is_dir_path = if original_path.ends_with?('/') && !expanded_path.ends_with? '/'
                      expanded_path = expanded_path + '/'
                      true
                    else
                      expanded_path.ends_with? '/'
                    end

      file_path = File.join(@public_dir, expanded_path)

      if file = @cached_files[file_path]?
        last_modified = file[:filestat].modification_time
        add_cache_headers(context.response.headers, last_modified)

        if cache_request?(context, last_modified)
          context.response.status_code = 304
          return
        end

        send_file(context, file_path, file[:data], file[:filestat])
      else
        is_dir = Dir.exists? file_path

        if request_path != expanded_path
          redirect_to context, expanded_path
        elsif is_dir && !is_dir_path
          redirect_to context, expanded_path + '/'
        end

        if Dir.exists?(file_path)
          if config.is_a?(Hash) && config["dir_listing"] == true
            context.response.content_type = "text/html"
            directory_listing(context.response, request_path, file_path)
          else
            call_next(context)
          end
        elsif File.exists?(file_path)
          last_modified = modification_time(file_path)
          add_cache_headers(context.response.headers, last_modified)

          if cache_request?(context, last_modified)
            context.response.status_code = 304
            return
          end

          if @cached_files.sum { |element| element[1][:data].bytesize } + (size = File.size(file_path)) < CACHE_LIMIT
            data = Bytes.new(size)
            File.open(file_path) do |file|
              file.read(data)
            end
            filestat = File.info(file_path)

            @cached_files[file_path] = {data: data, filestat: filestat}
            send_file(context, file_path, data, filestat)
          else
            send_file(context, file_path)
          end
        else
          call_next(context)
        end
      end
    end
  end
end
