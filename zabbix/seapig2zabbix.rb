#!/bin/env ruby
#
#
#

require 'seapig-client'
require 'eventmachine'
require 'awesome_print'

EM.run {
	workers = SeapigClient.new('http://127.0.0.1:3001/seapig', name: 'zabbix-monitor').slave('workers')
	EM.add_periodic_timer(30) {
		workers['workers'].each { |worker|
			if not worker['resources'].nil?
				worker['resources'].each { |resource|
					if resource['estimated_release_time'].nil?
						next
					end
					#puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
					#puts "#{worker['name']}: #{resource['id']} #{resource['type']} #{resource['task_id']} #{resource['estimated_release_time']}"
					cmd =  "/bin/zabbix_sender"
					cmd += " --zabbix-server zabbix-server"
					cmd += " --host " + worker['name']
					cmd += " --key 'scheduler.worker.resource[" + resource['type']
					cmd += "," + resource['id'].to_s
					cmd += "]' --value " + resource['estimated_release_time'].to_s
					#puts cmd
					`#{cmd}`
				}
			end
		}
    	}
}
