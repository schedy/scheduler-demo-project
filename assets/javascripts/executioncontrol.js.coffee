Toaster =
        save: (message)->
                  document.getElementById('toast-icon').innerHTML = message[0]
                  document.getElementById('toast-desc').innerHTML = message[1]
                  x = document.getElementById('toast')
                  x.className = 'show'
                  setTimeout (->
                    x.className = x.className.replace('show', '')
                    return
                  ), 5000

upload = (e) ->
  files = e.target.files
  data = new FormData
  i = 0
  while i < files.length
    data.append 'file' + i, files[i]
    i++
  console.log(data)
  execution.current.archives = data
  console.log(execution.current)
  return


execution =
        submit_in_progress: false
        save: ->
            execution.submit_in_progress = true
            m.request(
              method: 'POST'
              url: '/executions/create/schedy_manual.rb'
              data: execution.current).then((result)->
                execution.submit_in_progress = false
                Toaster.save(["✅","Execution "+result.id+" is created !"])
                return).catch (e) ->
                        execution.submit_in_progress = false
                        Toaster.save(["❌","Execution creation failed."])
                        console.log(e)

        response: ""

        current:
                default_project: ''
                project: ''
                package: ''
                triggered_by_package: ''
                arch: ''
                repo: ''
                multiplier: ''
                event_type: ''
                target_resources: ''
                author: ''
                url_gerrit: ''
                target_tag: ''
                target_name: ''
                description: ''
                archives : null

##possible properties,
# project -> must be a project in obs -> https://obs/build/source/<project> must return 200
# package -> must be a package in obs -> https://obs/build/source/<project>/<package> must return 200
# repo -> must be a repo in obs -> https://obs/build/build/<project>/<repo> must return 200
# arch -> must be a arch in obs -> https://obs/build/build/<project>/<repo>/<arch> must return 200
# event_type -> must be in list of event_types
# resource_id -> must be integer
# multiplier -> must be integer
# author -> must be string
# gerrit url -> must be url
#
window.Executioncontrol =

        view: (vnode)->
            m '.',

                    m 'div',{id: "toast"},
                        m 'div',{id: "toast-icon"},"Icon"
                        m 'div',{id: "toast-desc"}, "Message"

                    m 'form', { onsubmit: (e) ->
                        e.preventDefault()
                        execution.response = execution.save()
                        },
                                m '.container-fluid.new-execution-form',
                                        m "h2",{style: { "padding": "10px" } },"Create New Execution"

                                        m '.col-md-12',
                                                m '.row',
                                                        m '.col-md-6.form-group',
                                                                m 'label.project',"Default Project"
                                                                m 'input.form-control',
                                                                    {oninput: m.withAttr("value", (e) ->
                                                                            execution.current.default_project = e
                                                                            ),
                                                                    value: execution.current.default_project,
                                                                    placeholder: "e.g. builder1:37031:1"}
                                                        m '.col-md-6.form-group',
                                                                m 'label',"Project"
                                                                m 'input.form-control',
                                                                    {oninput: m.withAttr("value", (e) ->
                                                                            execution.current.project = e
                                                                            ),
                                                                    value: execution.current.project,
                                                                    placeholder: "e.g. builder1:37031:1"}
                                                m '.row',
                                                        m '.col-md-6.form-group',
                                                                m 'label',"Triggered By Package"
                                                                m 'input.form-control',
                                                                    {oninput: m.withAttr("value", (e) ->
                                                                            execution.current.triggered_by_package = e
                                                                            ),
                                                                    value: execution.current.triggered_by_package,
                                                                    placeholder: "e.g. obspackage"}
                                                        m '.col-md-6.form-group',
                                                                m 'label',"Package"
                                                                m 'input.form-control',
                                                                    {oninput: m.withAttr("value", (e) ->
                                                                            execution.current.package = e
                                                                            ),
                                                                    value: execution.current.package,
                                                                    placeholder: "e.g. obspackage"}
                                                m '.row',
                                                        m '.col-md-6.form-group',
                                                                m 'label',"Architecture"
                                                                m 'input.form-control',
                                                                    {oninput: m.withAttr("value", (e) ->
                                                                            execution.current.arch = e
                                                                            ),
                                                                     # onchange: m.withAttr("value", (e) ->
                                                                     #        validate_input("arch",e)
                                                                     #        ),
                                                                    value: execution.current.arch,
                                                                    placeholder: "e.g. i586, x86_64"}
                                                        m '.col-md-6.form-group',
                                                                m 'label',"Repository"
                                                                m 'input.form-control',
                                                                    {oninput: m.withAttr("value", (e) ->
                                                                            execution.current.repo = e
                                                                            ),
                                                                     # onchange: m.withAttr("value", (e) ->
                                                                     #        validate_input("repo",e)
                                                                     #        ),
                                                                    value: execution.current.repo,
                                                                    placeholder: "e.g. obsrepo"}
                                                m '.row',
                                                        m '.col-md-6.form-group',
                                                                m 'label',"Multiplier"
                                                                m 'input.form-control',
                                                                    {oninput: m.withAttr("value", (e) ->
                                                                            execution.current.multiplier = e
                                                                            ),
                                                                     # onchange: m.withAttr("value", (e) ->
                                                                     #        validate_input("multiplier",e)
                                                                     #        ),
                                                                    value: execution.current.multiplier,
                                                                    placeholder: "1,2..."}
                                                        m '.col-md-6.form-group',
                                                                m 'label',"Event Type"
                                                                m 'input.form-control',
                                                                    {oninput: m.withAttr("value", (e) ->
                                                                            execution.current.event_type = e
                                                                            ),
                                                                     # onchange: m.withAttr("value", (e) ->
                                                                     #        validate_input("event_type",e)
                                                                     #        ),
                                                                    value: execution.current.event_type,
                                                                    placeholder: "e.g. manual, master_merge"}
                                                # m '.row',
                                                #         m '.col-md-6.form-group',
                                                #                 m 'label',"Target Resource ID"
                                                #                 m 'input.form-control',
                                                #                     {oninput: m.withAttr("value", (e) ->
                                                #                             execution.current.target_resources = e
                                                #                             ),
                                                #                      # onchange: m.withAttr("value", (e) ->
                                                #                      #        validate_input("resource_id",e)
                                                #                      #        ),
                                                #                     value: execution.current.target_resources,
                                                #                     placeholder: "e.g. 23,25,29"}

                                                m '.row',
                                                        m '.col-md-6.form-group',
                                                                m 'label',"Target Name"
                                                                m 'input.form-control',
                                                                    {oninput: m.withAttr("value", (e) ->
                                                                            execution.current.target_name = e
                                                                            ),
                                                                     # onchange: m.withAttr("value", (e) ->
                                                                     #        validate_input("target_tag",e)
                                                                     #        ),
                                                                    value: execution.current.target_name,
                                                                    placeholder: "e.g. test_1|test_2"}
                                                        m '.col-md-6.form-group',
                                                                m 'label',"Target Tag"
                                                                m 'input.form-control',
                                                                    {oninput: m.withAttr("value", (e) ->
                                                                            execution.current.target_tag = e
                                                                            ),
                                                                     # onchange: m.withAttr("value", (e) ->
                                                                     #        validate_input("target_tag",e)
                                                                     #        ),
                                                                    value: execution.current.target_tag,
                                                                    placeholder: "e.g. smoke_test, sanity_test"}
                                                # m '.row',
                                                #         m '.col-md-6',
                                                #                 m 'label',"Archives"
                                                #                 m 'input',{"type": "file","multiple": "true",onchange: upload}

                                                m '.row',

                                                                m 'button.btn.btn-primary.pull-right',{"type":"submit"},
                                                                                                                        if not execution.submit_in_progress
                                                                                                                                "Submit"
                                                                                                                        else
                                                                                                                                m 'span', "In Progress...",
                                                                                                                                        m '.spinner', "↺"
