module Ga4gh
  module Trs
    module V2
      class GeneralController < ActionController::API
        respond_to :json

        def service_info
          id = URI(Seek::Config.site_base_host).host.split('.').reverse.join('.') rescue nil
          id ||= 'misc-seek-deployment'
          respond_with({
              "contactUrl": "mailto:#{Seek::Config.support_email_address}",
              "createdAt": "2019-06-04T12:58:19Z",
              "description": "TRS API endpoint for #{Seek::Config.application_name}",
              "documentationUrl": "https://editor.swagger.io/?url=https://raw.githubusercontent.com/ga4gh/tool-registry-schemas/develop/openapi/ga4gh-tool-discovery.yaml",
              "environment": Rails.env,
              "id": id,
              "name": Seek::Config.application_name,
              "organization": {
                  "name": Seek::Config.dm_project_name,
                  "url": Seek::Config.dm_project_link
              },
              "type": {
                  "artifact": "trs",
                  "group": "org.ga4gh",
                  "version": "1.0.0"
              },
              "updatedAt": "2019-06-04T12:58:19Z",
              "version": "1.0.0"
          }.to_json)
        end

        def tool_classes
          respond_with([ToolClass::WORKFLOW], adapter: :attributes)
        end
      end
    end
  end
end
