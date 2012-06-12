# Datacenter view
module 'DatacenterView', ->
    # Container
    class @Container extends Backbone.View
        className: 'datacenter-view'
        template: Handlebars.compile $('#datacenter_view-container-template').html()
        events: ->
            'click a.rename-datacenter': 'rename_datacenter'
            'click .display_more_machines': 'expand_profile'
            'click .close': 'close_alert'
            
        max_log_entries_to_render: 3

        initialize: (id) =>
            log_initial '(initializing) datacenter view: container'
            @datacenter_uuid = id

        rename_datacenter: (event) ->
            event.preventDefault()
            rename_modal = new UIComponents.RenameItemModal @model.get('id'), 'datacenter'
            rename_modal.render()
            @title.update()

        wait_for_model_noop: ->
            return true

        wait_for_model: =>
            @model = datacenters.get(@datacenter_uuid)
            if not @model
                datacenters.off 'all', @render
                datacenters.on 'all', @render
                return false

            # Model is finally ready, bind necessary handlers
            datacenters.off 'all', @render


            # Everything has been set up, we don't need this logic any
            # more
            @wait_for_model = @wait_for_model_noop

            return true

        render_empty: =>
            @.$el.text 'Datacenter ' + @datacenter_uuid + ' is not available.'
            return @

        render: =>
            log_render('(rendering) datacenter view: container')

            if @wait_for_model() is false
                return @render_empty()
            
            @title = new DatacenterView.Title(@datacenter_uuid)
            @profile = new DatacenterView.Profile(@datacenter_uuid)
            @data = new DatacenterView.Data(@datacenter_uuid)

            stats = @model.get_stats_for_performance
            @performance_graph = new Vis.OpsPlot(stats)
            
            @stats_panel = new Vis.StatsPanel(stats)

            @.$el.html @template

            # fill the title of this page
            @.$('.main_title').html @title.render().$el

            # fill the profile (name, reachable...)
            @.$('.profile').html @profile.render().$el
            @.$('.performance-graph').html @performance_graph.render().$el

            # display the data on the machines
            @.$('.datacenter-stats').html @stats_panel.render().$el

            # display the data on the machines
            @.$('.data').html @data.render().$el

            # Filter all the machines for those belonging to this datacenter and append logs
            machines_in_datacenter = machines.filter (machine) => return machine.get('datacenter_uuid') is @model.get('id')

            dc_log_entries = new LogEntries
            for machine in machines_in_datacenter
                if machine.get('log_entries')?
                    dc_log_entries.add machine.get('log_entries').models

            entries_to_render = []
            dc_log_entries.each (log_entry) =>
                entries_to_render.push(new DatacenterView.RecentLogEntry
                    model: log_entry)
            entries_to_render = entries_to_render.slice(0, @max_log_entries_to_render)
            @.$('.recent-log-entries').append entry.render().el for entry in entries_to_render

            return @


        expand_profile: (event) ->
            event.preventDefault()
            @profile.more_link_should_be_displayed = false
            @.$('.more_machines').remove()
            @.$('.profile-expandable').css('overflow', 'auto')
            @.$('.profile-expandable').css('height', 'auto')



        close_alert: (event) ->
            event.preventDefault()
            $(event.currentTarget).parent().slideUp('fast', -> $(this).remove())

    # DatacenterView.Title
    class @Title extends Backbone.View
        className: 'datacenter-info-view'
        template: Handlebars.compile $('#datacenter_view_title-template').html()
        initialize: (uuid) =>
            @uuid = uuid
            @name = datacenters.get(@uuid).get('name')
            datacenters.on 'all', @update
        
        update: =>
            if @name isnt datacenters.get(@uuid).get('name')
                @name = datacenters.get(@uuid).get('name')
                @render()

        render: =>
            json =
                name: @name
            @.$el.html @template(json)
            return @
    class @Profile extends Backbone.View
        className: 'datacenter-info-view'

        template: Handlebars.compile $('#datacenter_view_profile-template').html()
        initialize: (id) =>
            @model = datacenters.get(id)

            @model.on 'all', @render
            machines.on 'all', @render
            directory.on 'all', @render

            @more_link_should_be_displayed = true


        render: =>
            # Filter all the machines for those belonging to this datacenter
            machines_in_datacenter = machines.filter (machine) => return machine.get('datacenter_uuid') is @model.get('id')

            # Data residing on this lovely datacenter
            _namespaces = []
            for namespace in namespaces.models
                _shards = []
                for machine_uuid, peer_roles of namespace.get('blueprint').peers_roles
                    if machines.get(machine_uuid).get('datacenter_uuid') is @model.get('id')
                        for shard, role of peer_roles
                            if role isnt 'role_nothing'
                                _shards[_shards.length] =
                                    role: role
                                    shard: shard
                                    name: human_readable_shard shard
                if _shards.length > 0
                    # Compute number of primaries and secondaries for each shard
                    __shards = {}
                    for shard in _shards
                        shard_repr = shard.shard.toString()
                        if not __shards[shard_repr]?
                            __shards[shard_repr] =
                                shard: shard.shard
                                name: human_readable_shard shard.shard
                                nprimaries: if shard.role is 'role_primary' then 1 else 0
                                nsecondaries: if shard.role is 'role_secondary' then 1 else 0
                        else
                            if shard.role is 'role_primary'
                                __shards[shard_repr].nprimaries += 1
                            if shard.role is 'role_secondary'
                                __shards[shard_repr].nsecondaries += 1

                    # Append the final data
                    _namespaces[_namespaces.length] =
                        shards: _.map(__shards, (shard, shard_repr) -> shard)
                        name: namespace.get('name')
                        uuid: namespace.id

            # make sure than the list of machines return contains first the one not reachable            
            machines_returned = []
            for machine in machines_in_datacenter
                status = DataUtils.get_machine_reachability(machine.get('id'))
                if status.reachable
                    machines_returned.push
                        name: machine.get('name')
                        id: machine.get('id')
                        status: status
                else
                    machines_returned.unshift
                        name: machine.get('name')
                        id: machine.get('id')
                        status: status

            # Generate json and render
            json =
                name: @model.get('name')
                list_machines:
                    machines: machines_returned
                    more_link_should_be_displayed: @more_link_should_be_displayed
                status: DataUtils.get_datacenter_reachability(@model.get('id'))
            stats = @model.get_stats()
            json = _.extend json,
                global_cpu_util: Math.floor(stats.global_cpu_util_avg * 100)
                global_mem_total: human_readable_units(stats.global_mem_total * 1024, units_space)
                global_mem_used: human_readable_units(stats.global_mem_used * 1024, units_space)
                dc_disk_space: human_readable_units(stats.dc_disk_space, units_space)
 
            @.$el.html @template(json)

            return @



    class @Data extends Backbone.View
        className: 'datacenter-data-view'

        template: Handlebars.compile $('#datacenter_view_data-template').html()
        initialize: (id) =>
            @model = datacenters.get(id)
            @model.on 'all', @render
            machines.on 'all', @render
            directory.on 'all', @render


        render: =>
            # Filter all the machines for those belonging to this datacenter
            machines_in_datacenter = machines.filter (machine) => return machine.get('datacenter_uuid') is @model.get('id')



            # Data residing on this lovely datacenter
            _namespaces = []
            for namespace in namespaces.models
                _shards = []
                for machine_uuid, peer_roles of namespace.get('blueprint').peers_roles
                    if machines.get(machine_uuid).get('datacenter_uuid') is @model.get('id')
                        for shard, role of peer_roles
                            if role isnt 'role_nothing'
                                _shards[_shards.length] =
                                    role: role
                                    shard: shard
                                    name: human_readable_shard shard
                if _shards.length > 0
                    # Compute number of primaries and secondaries for each shard
                    __shards = {}
                    for shard in _shards
                        shard_repr = shard.shard.toString()
                        if not __shards[shard_repr]?
                            __shards[shard_repr] =
                                shard: shard.shard
                                name: human_readable_shard shard.shard
                                nprimaries: if shard.role is 'role_primary' then 1 else 0
                                nsecondaries: if shard.role is 'role_secondary' then 1 else 0
                        else
                            if shard.role is 'role_primary'
                                __shards[shard_repr].nprimaries += 1
                            if shard.role is 'role_secondary'
                                __shards[shard_repr].nsecondaries += 1

                    # Append the final data
                    _namespaces[_namespaces.length] =
                        shards: _.map(__shards, (shard, shard_repr) -> shard)
                        name: namespace.get('name')
                        uuid: namespace.id
            # Generate json and render
            json =
                data:
                    namespaces: _namespaces
            stats = @model.get_stats()
            json = _.extend json,
                global_cpu_util: Math.floor(stats.global_cpu_util_avg * 100)
                global_mem_total: human_readable_units(stats.global_mem_total * 1024, units_space)
                global_mem_used: human_readable_units(stats.global_mem_used * 1024, units_space)
                dc_disk_space: human_readable_units(stats.dc_disk_space, units_space)
 
            @.$el.html @template(json)

            return @



    # DatacenterView.RecentLogEntry
    class @RecentLogEntry extends Backbone.View
        className: 'recent-log-entry'
        template: Handlebars.compile $('#datacenter_view-recent_log_entry-template').html()

        events: ->
            'click a[rel=popover]': 'do_nothing'

        do_nothing: (event) -> event.preventDefault()

        render: =>
            json = _.extend @model.toJSON(), @model.get_formatted_message()
            @.$el.html @template _.extend json,
                machine_name: machines.get(@model.get('machine_uuid')).get('name')
                timeago_timestamp: @model.get_iso_8601_timestamp()

            @.$('abbr.timeago').timeago()
            @.$('a[rel=popover]').popover
                html: true
            return @