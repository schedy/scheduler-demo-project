#!/bin/env ruby

require 'bundler/setup'

require '../../config/environment.rb'
require 'rest-client'
require '../config.rb'

def robot_xml_merger(execution_id, cwd)
  task_xmls = []
  workitem = Execution.find(execution_id.to_i)
  task_ids = workitem.tasks.pluck(:id)
  Execution.find(execution_id.to_i).tasks.map { |task|
    task.artifacts.where('name' => 'output.xml').map { |xml|
      xml_path = "#{cwd}/#{xml.id.to_s}"
      File.open(xml_path, "w:ASCII-8BIT"){ |f|
        f.write(xml.data)
      }
      task_xmls.push(xml_path)
    }
  }

  if task_xmls.size() > 0
    merge_order = ['/usr/bin/rebot','--name','Execution_Results','--output','output.xml'].push(task_xmls).flatten.join(' ')
    puts merge_order
    puts `#{merge_order}`

    if File.exist?('output.xml') && File.exists?('log.html')
      RestClient.post(EXTERNAL_SCHEDULER_URI+'/artifacts', execution: execution_id, data: File.new('output.xml'))
      RestClient.post(EXTERNAL_SCHEDULER_URI+'/artifacts', execution: execution_id, data: File.new('log.html'))
    end
  else
    puts "no artifacts found!"
  end # if
end # def

###################################################
# MAIN
###################################################
execution_id = ARGV[0]
status = ARGV[1]

if status == "finished"
  Dir.mktmpdir("robot_xml_merger-") {|tmpdir|
    puts "#{execution_id} - #{status} - #{tmpdir}"
    Dir.chdir(tmpdir){ |path|
      robot_xml_merger(execution_id, path)
    }
  }
end
