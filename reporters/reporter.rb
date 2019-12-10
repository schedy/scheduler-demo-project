#!/bin/env ruby
require '../../config/environment.rb'
require 'rest_client'
require "awesome_print"
require 'json'
require '../config.rb'

#ActiveRecord::Base.logger = Logger.new(STDERR)
$server = RestClient::Resource.new(DASHBOARD_URI)

$packages = [ ]

def melt_data(executions)
        executions.map { |execution|
                {
                        created_at: execution.created_at.iso8601,
                        patchset_id: execution.patchset_id,
                        change_id: execution.change_id,
                        package_name: execution.package,
                        execution_id: execution.id,
                        gerrit_url: execution.gerrit_url,
                        author: execution.author,
                        subject: execution.subject,
                        results: execution.tasks_summary,
                        version_info: execution.versions
                }
        }.group_by { |d| d[:package_name] }
end


def get_executions(packages, event_type, limit)
        $fail_value ||= Value.where(value: 'FAIL').first.id
        $pass_value ||= Value.where(value: 'PASS').first.id

        Execution.find_by_sql(["
                select
                        packages.value as package,
                        execs.id,
                        execs.created_at,
                        (select values.value from values, execution_values where values.property_id = 5 and execution_values.value_id = values.id and execution_values.execution_id = execs.id) as gerrit_url,
                        (select values.value from values, execution_values where values.property_id = 6 and execution_values.value_id = values.id and execution_values.execution_id = execs.id) as author,
                        substring((select values.value from values, execution_values where values.property_id = 2 and execution_values.value_id = values.id and execution_values.execution_id = execs.id) from '%:#\"%#\":[^:]+' for '#') as patchset_id,
                        substring((select values.value from values, execution_values where values.property_id = 2 and execution_values.value_id = values.id and execution_values.execution_id = execs.id) from '%:#\"[^:]+#\"' for '#') as change_id,
                        '' as subject,
                        coalesce((select json_object_agg(name, json_build_object('pass_count', passes, 'fail_count', fails))
                                from (select name, sum(passes) as passes, sum(fails) as fails
                                        from (select
                                             coalesce((select values.value from values, task_values where values.property_id = 3 and task_values.value_id = values.id and task_values.task_id = tasks.id),'') as name,
                                                    count(passes) as passes, count(fails) as fails
                                              from tasks
                                                    left outer join task_values passes on (tasks.id = passes.task_id and passes.value_id = 4)
                                                    left outer join task_values fails on (tasks.id = fails.task_id and fails.value_id = 9)
                                              where
                                                    execution_id = execs.id group by tasks.id) xxx
                                              group by name) yyy), '{}'::json) as tasks_summary,
                        (select tasks.description -> 'requirements' -> 0 ->>'archives' from tasks where tasks.execution_id = execs.id limit 1) as versions
                from
                        (select values.id, values.value from values where values.id in (?)) packages,
                        lateral
                        (select executions.* from executions
                                LEFT JOIN execution_values ev_package ON executions.id = ev_package.execution_id
                                LEFT JOIN execution_values ev_eventtype ON executions.id = ev_eventtype.execution_id
                        WHERE ev_package.value_id = packages.id
                                AND ev_eventtype.value_id = (select values.id from values, properties where values.property_id = properties.id AND properties.name = 'eventtype' AND value = ?)
                        order by executions.id desc limit ?) execs
                order by execs.id
         ", packages, event_type, limit])
end


def update_report(report_id,master_execution_count,patch_execution_count,primary_event_type,secondary_event_type)
        packages = Property.where(name: 'package').first.values.select { |value| $packages.include?(value.value) }.map { |value| value.id }

        last_master_executions = get_executions(packages,primary_event_type,master_execution_count.to_i)
        last_patch_executions = get_executions(packages,secondary_event_type,patch_execution_count.to_i) if patch_execution_count.to_i > 0

        outgoing = melt_data(last_master_executions)
        outgoing = {master: outgoing, devel: melt_data(last_patch_executions)} if patch_execution_count.to_i > 0

        puts "Uploaded report: %i"%JSON.parse($server["/reports/"+report_id.to_s+"/versions.json"].post(content: JSON.dump({ data: outgoing })), symbolize_names: true)[:version]
end


def update_reports()
        $previous_version ||= 0
        version = SeapigDependency.uncached{SeapigDependency.find_by("name = 'TaskValue'").current_version}
        return if version == $previous_version
        $previous_version = version
        update_report(6,18,0,'nightly',nil)
        update_report(5,200,0,'nightly',nil)
        update_report(1,20,0,'master_merge',nil)
        update_report(4,5,12,'master_merge','manual')
        update_report(3,10,8,'master_merge','gerrit_pull_request')
end

update_reports()


ActiveRecord::Base.connection_pool.with_connection { |connection|
        connection = connection.instance_variable_get(:@connection)
        connection.exec("LISTEN seapig_dependency_changed")
        loop {
                connection.wait_for_notify { |channel, pid, payload|
                        update_reports
                }
        }
}
