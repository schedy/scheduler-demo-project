$(document).keypress (e) ->
        if (e.charCode == 112)
                $(".task_status_finished").css("background-color", "pink")
