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

module JSONFilter
  alias BracketIndex = Hash(Int64, Int64)

  alias GroupedFieldsValue = String | Array(GroupedFieldsValue)
  alias GroupedFieldsList = Array(GroupedFieldsValue)

  class FieldsParser
    class ParseError < Exception
    end

    def self.nest_group_pattern : Regex
      /(?:|,)(?<groupname>[^,\n]*?)\(/
    end

    def self.unnamed_nest_group_pattern : Regex
      /(?:|,)(?<groupname>[^,\n]*?)\(/
    end

    def self.parse_fields(fields_text : String) : Nil
      if fields_text.empty?
        raise FieldsParser::ParseError.new "Field is empty"
      end

      opening_bracket_count = fields_text.count('(')
      closing_bracket_count = fields_text.count(')')

      if opening_bracket_count != closing_bracket_count
        bracket_type = opening_bracket_count > closing_bracket_count ? "opening" : "closing"
        raise FieldsParser::ParseError.new "There are too many #{bracket_type} brackets (#{opening_bracket_count}:#{closing_bracket_count})"
      elsif match_result = unnamed_nest_group_pattern.match(fields_text)
        raise FieldsParser::ParseError.new "Unnamed nest group at position #{match_result.begin}"
      end

      parse_single_nests(fields_text) { |nest_list| yield nest_list }

      parse_nest_groups(fields_text) { |nest_list| yield nest_list }
    end

    def self.parse_single_nests(fields_text : String) : Nil
      single_nests = remove_nest_groups(fields_text)

      if !single_nests.empty?
        property_nests = single_nests.split(',')

        property_nests.each do |nest|
          nest_list = nest.split('/')
          if nest_list.includes? ""
            raise FieldsParser::ParseError.new "Empty key in nest list: #{nest_list}"
          end
          yield nest_list
        end
      end
    end

    def self.parse_nest_groups(fields_text : String) : Nil
      nest_stack = [] of NamedTuple(group_name: String, closing_bracket_index: Int64)
      bracket_pairs = get_bracket_pairs(fields_text, true)

      text_index = 0
      regex_index = 0

      while regex_result = self.nest_group_pattern.match(fields_text, regex_index)
        raw_match = regex_result[0]
        group_name = regex_result["groupname"]

        text_index = regex_result.begin
        regex_index = regex_result.end

        if text_index.nil? || regex_index.nil?
          raise FieldsParser::ParseError.new "Received invalid index while parsing nest groups: text_index: #{text_index} | regex_index: #{regex_index}"
        end

        offset = raw_match.starts_with?(',') ? 1 : 0
        opening_bracket_index = (text_index + group_name.size) + offset
        closing_bracket_index = bracket_pairs[opening_bracket_index]
        content_start = opening_bracket_index + 1

        content = fields_text[content_start...closing_bracket_index]

        if content.empty?
          raise FieldsParser::ParseError.new "Empty nest group at position #{content_start}"
        else
          content = remove_nest_groups(content)
        end

        while nest_stack.size > 0 && closing_bracket_index > nest_stack[nest_stack.size - 1][:closing_bracket_index]
          if nest_stack.size
            nest_stack.pop
          end
        end

        group_name.split('/').each do |group_name|
          nest_stack.push({
            group_name:            group_name,
            closing_bracket_index: closing_bracket_index,
          })
        end

        if !content.empty?
          properties = content.split(',')

          properties.each do |prop|
            nest_list = nest_stack.map { |nest_prop| nest_prop[:group_name] }

            if !prop.empty?
              if prop.includes?('/')
                parse_single_nests(prop) { |list| nest_list += list }
              else
                nest_list.push prop
              end
            else
              raise FieldsParser::ParseError.new "Empty key in nest list: #{nest_list << prop}"
            end

            yield nest_list
          end
        end
      end
    end

    def self.remove_nest_groups(text : String) : String
      content_bracket_pairs = get_bracket_pairs(text, false)

      content_bracket_pairs.each_key.to_a.reverse.each do |opening_bracket|
        closing_bracket = content_bracket_pairs[opening_bracket]
        last_comma = text.rindex(',', opening_bracket) || 0

        text[0...last_comma] + text[closing_bracket + 1...text.size]
      end

      return text.starts_with?(',') ? text[1...text.size] : text
    end

    def self.get_bracket_pairs(text : String, recursive = true) : BracketIndex
      istart = [] of Int64
      bracket_index = BracketIndex.new

      text.each_char_with_index do |char, index|
        if char == '('
          istart.push(index.to_i64)
        end

        if char == ')'
          begin
            opening = istart.pop
            if recursive || (!recursive && istart.size == 0)
              bracket_index[opening] = index.to_i64
            end
          rescue
            raise FieldsParser::ParseError.new "No matching closing parenthesis at: #{index}"
          end
        end
      end

      if istart.size != 0
        idx = istart.pop
        raise FieldsParser::ParseError.new "No matching closing parenthesis at: #{idx}"
      end

      return bracket_index
    end
  end

  class FieldsGrouper
    alias SkeletonValue = Hash(String, SkeletonValue)

    def self.create_json_skeleton(fields_text : String) : SkeletonValue
      root_hash = {} of String => SkeletonValue

      FieldsParser.parse_fields(fields_text) do |nest_list|
        current_item = root_hash

        nest_list.each do |key|
          if current_item[key]?
            current_item = current_item[key]
          else
            current_item[key] = {} of String => SkeletonValue
            current_item = current_item[key]
          end
        end
      end
      root_hash
    end

    def self.create_grouped_fields_list(json_skeleton : SkeletonValue) : GroupedFieldsList
      grouped_fields_list = GroupedFieldsList.new

      json_skeleton.each do |key, value|
        grouped_fields_list.push key

        nested_keys = create_grouped_fields_list(value)
        grouped_fields_list.push nested_keys unless nested_keys.empty?
      end

      return grouped_fields_list
    end
  end

  class FilterError < Exception
  end

  def self.filter(item : JSON::Any, fields_text : String, in_place : Bool = true)
    skeleton = FieldsGrouper.create_json_skeleton(fields_text)
    grouped_fields_list = FieldsGrouper.create_grouped_fields_list(skeleton)
    filter(item, grouped_fields_list, in_place)
  end

  def self.filter(item : JSON::Any, grouped_fields_list : GroupedFieldsList, in_place : Bool = true) : JSON::Any
    item = item.clone unless in_place

    if !item.as_h? && !item.as_a?
      raise FilterError.new "Can't filter '#{item}' by #{grouped_fields_list}"
    end

    top_level_keys = Array(String).new
    grouped_fields_list.each do |value|
      if value.is_a? String
        top_level_keys.push value
      elsif value.is_a? Array
        if !top_level_keys.empty?
          key_to_filter = top_level_keys.last

          if item.as_h?
            filter(item[key_to_filter], value, in_place: true)
          elsif item.as_a?
            item.as_a.each { |arr_item| filter(arr_item[key_to_filter], value, in_place: true) }
          end
        else
          raise FilterError.new "Tried to filter while top level keys list is empty"
        end
      end
    end

    if item.as_h?
      item.as_h.select! top_level_keys
    elsif item.as_a?
      item.as_a.map { |value| filter(value, top_level_keys, in_place: true) }
    end

    item
  end
end
