module Librato
  module Rails
    # controllers
    ActiveSupport::Notifications.subscribe('!render_template.action_view') do |*args|

      event = ActiveSupport::Notifications::Event.new(*args)
      path = event.payload[:virtual_path]

      exception = event.payload[:exception]
      # page_key = "request.#{controller}.#{action}_#{format}."

      view_name = path.gsub(/\//, '.')

      record_view = Proc.new do |r|

        r.increment 'total'
        r.timing    'time', event.duration


        if exception
          r.increment 'exceptions'
        end

        r.increment 'slow' if event.duration > 50.0
      end# end group

      group 'rails.view', &record_view
      group "rails.view.#{view_name}", &record_view

    end

    ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*args|

      event = ActiveSupport::Notifications::Event.new(*args)
      controller = event.payload[:controller]
      action = event.payload[:action]

      format = event.payload[:format] || "all"
      format = "all" if format == "*/*"
      status = event.payload[:status]
      method = event.payload[:method]
      exception = event.payload[:exception]
      # page_key = "request.#{controller}.#{action}_#{format}."

      controller_name = ((m = controller.match(/(.+)Controller/)) && m[1].downcase) || controller
      action_name = event.payload[:action]

      record_controller = Proc.new do |r|

        r.increment 'total'
        r.timing    'time', event.duration

        if exception
          r.increment 'exceptions'
        else
          r.timing 'time.db', (db_runtime = event.payload[:db_runtime] || 0)
          r.timing 'time.view', (view_runtime = event.payload[:view_runtime] || 0)
          r.timing 'time.controller', event.duration - (db_runtime + view_runtime)
        end

        unless status.blank?
          r.group 'status' do |s|
            s.increment status
            s.increment "#{status.to_s[0]}xx"
            s.timing "#{status}.time", event.duration
            s.timing "#{status.to_s[0]}xx.time", event.duration
          end
        end

        r.increment 'slow' if event.duration > 200.0
      end# end group

      group 'rails.request', &record_controller
      group "rails.controller.#{controller_name}", &record_controller
      group "rails.controller.#{controller_name}.#{action_name}.#{method}", &record_controller

    end # end subscribe

    # SQL

    ActiveSupport::Notifications.subscribe 'sql.active_record' do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      payload = event.payload

      model_name = case payload[:name]
        when 'SCHEMA' then payload[:binds].flatten.compact.join('_').singularize
        when 'CACHE', '', nil then nil
        else payload[:name].split(' ')[0].downcase
      end

      if payload[:name] == 'CACHE'
        timing "rails.model.cache", event.duration
      end

      record_model = Proc.new do |s|
        # puts (event.payload[:name] || 'nil') + ":" + event.payload[:sql] + "\n"
        s.increment 'queries.total'
        s.timing 'queries.time', event.duration

        sql = payload[:sql].strip
        command = (m = sql.match(/\A([A-Z]+) /)) && m[1]
        if command
          s.group "#{command.downcase}" do |c|
            c.increment 'total'
            c.timing 'time', event.duration
          end
        end
      end

      group "rails.sql", &record_model
      if model_name
        group "rails.model.#{model_name}", &record_model
      end
    end

    # ActionMailer

    ActiveSupport::Notifications.subscribe 'deliver.action_mailer' do |*args|
      # payload[:mailer] => 'UserMailer'
      group "rails.mail" do |m|
        m.increment 'sent'
      end
    end

    ActiveSupport::Notifications.subscribe 'receive.action_mailer' do |*args|
      group "rails.mail" do |m|
        m.increment 'received'
      end
    end

  end
end