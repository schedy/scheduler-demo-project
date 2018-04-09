require_relative "./task_procedure.rb"
class ExecutionCreator
	def self.create_execution(description)

		tasks = ([TaskProcedure.create_tasks(description)] or []).compact.flatten
		gating_tag = TaskProcedure.get_config(description,description.triggered_by_package)["gating_tag"]
		gating_threshold = TaskProcedure.get_config(description,description.triggered_by_package)["gating_threshold"]

		tags = {}

		if description.triggered_by_package then tags[:package]     = [description.triggered_by_package]                   end
		if description.project              then tags[:project]     = [description.project]                                end
		if description.author               then tags[:author]      = [description.author]                                 end
		if description.url_gerrit           then tags[:gerrit]      = [description.url_gerrit]                             end
		if description.url_obs              then tags[:obs]         = [description.url_obs]                                end
		if description.event_type           then tags[:eventtype]   = [description.event_type]                             end
		if description.hooks                then hooks              = description.hooks
		else hooks                                                  = {"finished": ["bureaucrat.rb","data_exporter.rb"]}   end
		if gating_threshold                 then tags[:threshold]   = [gating_threshold]                                   end
		if gating_tag                       then tags[:gating_tag]  = [gating_tag]                                         end				

		execution = {tasks: tasks, creator: "CI", tags: tags, data: nil, hooks: hooks}

		return execution
	end
end
