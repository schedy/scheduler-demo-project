#!/bin/env ruby

require '../../config/environment.rb'

require 'rest-client'
require 'json'

SERVER_URL = "http://dashboard/"


def upload(file_name)
	puts JSON.parse(RestClient::Request.new(method: :post, url: SERVER_URL + 'data/schedy-execution-1', payload: {multipart: true, file: File.new(file_name)}).execute.body)
end

def export_data(execution_id, path)
	eventtype_property_id = Property.find_by(name: "eventtype").id
	execution = Execution.includes(execution_values: { value: [:property] }, tasks: {task_values: [:value]}).find(execution_id)

	data = {
		id: execution_id,
		created_at: execution.created_at,
		tags: execution.execution_values.map { |execution_value| [execution_value.value.property.name, execution_value.value.value] },
		workitem: execution.data,
		tasks: execution.tasks.map { |task|
			measurements = {}
			task.artifacts.where("name like 'measurement_%'").each { |artifact|
				(measurements[artifact.name.split("_",2)[1]] ||= []) << artifact.data
			}
			{
				id: task.id,
				created_at: task.created_at,
				status: task.status.status,
				tags: task.task_values.map { |task_value| [task_value.value.property.name, task_value.value.value] },
				archives: task.description["archives"],
				resources: task.resource_statuses.map { |resource_status| { worker: resource_status.resource.worker.name, remote_id: resource_status.resource.remote_id, description: resource_status.description } },
				measurements: measurements
			}
		}
	}

	File.open('data.json', 'w') {|f| f.write(JSON.dump(data)) }
	puts `tar cvjf data.tar.bz2 data.json`
	upload("data.tar.bz2")
end


###################################################
## MAIN
####################################################
execution_id = ARGV[0]
status = ARGV[1]

if status == "finished"
	Dir.mktmpdir("data-exporter-hook-") {|tmpdir|
		puts "#{execution_id} - #{status} - #{tmpdir}"
		Dir.chdir(tmpdir){ |path|
			export_data(execution_id, path)
		}
	}
end
