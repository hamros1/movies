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

class ProcessRunner
  property processes = Hash(String, Array(Process)).new
  property process_name : String

  def initialize(
    @process_name : String,
    @run_commands = Hash(String, String).new,
    @includes = Hash(String, Array(String)).new
  )
  end

  def run
    scan_files(no_actions: true)
    start_processes

    loop do
      scan_files
      check_processes
      sleep 1
    end
  end

  private def scan_files(no_actions = false)
    all_files = Hash(String, Array(String)).new # { "file" => [ "task1", "task2" ]}

    @includes.each do |task, includes|
      includes.each do |glob|
	Dir.glob(glob).each do |f|
	  all_files[f] ||= Array(String).new
	  all_files[f] << task
	end
      end
    end

    return if no_actions

    tasks_to_run = Hash(String, Int32).new
    all_files.each do |file|
      all_files[file].each do |task|
	tasks_to_run[task] ||= 0
	tasks_to_run[task] += 1
      end
    end

    tasks_to_run.each do |task|
      start_processes(task)
    end
  end

  private def check_processes
    @processes.each do |task, procs|
      if procs.any?
	procs.reject!(&.terminated?)
	if procs.empty?
	  if task == "run"
	    start_processes(task)
	  else
	  end
	end
      end
    end
  end

  private def stop_processes
    @processes.each do |task, procs|
      next unless task_to_stop == :all || task_to_stop.to_s == task

      procs.each do |process|
	process.kill unless process.terminated?
      end
      procs.clear
    end
  end

  private def start_processes(task_to_start = :all)
    if task_to_start == :all || task_to_start == "run"
      if run_command_run = @run_commands["run"]
	start_process(run_command_run)
      end
    end

    run_commands(task_to_start)
  end

  private def start_process(run_command_run)
    process = run(run_command_run, wait: false, shell: false)
    if process.is_a? Process
      @processes["run"] ||= Array(Process).new
      @processes["run"] << process
#    elsif process.is_a? Exception
#      exit 1
    end
  end

  private def run_commands(task_to_start)
    @run_commands.each do |task, run_command|
      next if task == "run"
      next unless task_to_start == :all || task_to_start.to_s == task

      process = run(run_command, wait: false, shell: true)
      if process.is_a? Process
	@processes[task] ||= Array(Process).new
	@processes[task] << process
      end
    end
  end
end

def join_commands(command_array : Array(String)) : String
  case command_array.size
  when 0 then "echo"
  when 1 then command_array.first
  else
    command_array.map { |c| "(#{c})" }.join(" && ")
  end
end

