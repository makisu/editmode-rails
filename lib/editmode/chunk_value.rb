module Editmode
  class ChunkValue
    include ActionView::Helpers::TagHelper
    include ActionView::Context

    attr_accessor :identifier, :variable_values, :branch_id, 
                  :variable_fallbacks, :chunk_type, :project_id,
                  :url, :collection_id, :cache_identifier,
                  :response

    attr_writer :content

    def initialize(identifier, **options)
      @identifier = identifier
      @branch_id = options[:branch_id].presence
      @project_id = Editmode.project_id
      @variable_values = options[:variables].presence || {}
      @raw = options[:raw].present?

      @url = "#{api_root_url}/chunks/#{identifier}"
      @cache_identifier = set_cache_identifier(identifier)

      if options[:response].present?
        @response = options[:response]
        set_response_attributes!
      else
        get_content
      end
    end

    def field(field = nil)
      # Field ID can be a slug or field_name
      if chunk_type == 'collection_item'
        if field.present?
          field_chunk = field_chunk(field)
          if field_chunk.present?
            result = field_chunk['content']
            result = variable_parse!(result, variable_fallbacks, variable_values, @raw)
          else
            raise no_response_received(field)
          end
        else
          raise require_field_id
        end
      else
        raise "undefined method 'field` for chunk_type: #{chunk_type} \n"
      end
      result ||= @content
      result.try(:html_safe)
    end

    def field_chunk(field)
      field.downcase!
      @content.detect {|f| f["custom_field_identifier"].downcase == field || f["custom_field_name"].downcase == field }
    end

    def content
      raise "undefined method 'content' for chunk_type: collection_item \nDid you mean? field" if chunk_type == 'collection_item'

      result = variable_parse!(@content, variable_fallbacks, variable_values, @raw)
      result.try(:html_safe)
    end

    private

    def query_params
      the_params = { 'project_id' => project_id }
      the_params['branch_id'] = branch_id if branch_id.present?

      the_params
    end

    # Todo: Transfer to helper utils
    def api_root_url
      ENV["EDITMODE_OVERRIDE_API_URL"] || "https://api.editmode.com"
    end

    def set_cache_identifier(id)
      "chunk_#{project_id}#{branch_id}#{id}"
    end

    def json?(json)
      JSON.parse(json)
      return true
    rescue JSON::ParserError => e
      return false
    end

    def variable_parse!(content, variables = {}, values = {}, raw = true)
      content = ActionController::Base.helpers.sanitize(content)
      tokens = content.scan(/\{{(.*?)\}}/)
      if tokens.any?
        tokens.flatten!
        tokens.each do |token|
          token_value = values[token.to_sym] || variables[token] || ""
          sanitized_value = ActionController::Base.helpers.sanitize(token_value)

          unless raw
            sanitized_value = content_tag("em-var", :data => {chunk_variable: token, chunk_variable_value: sanitized_value}) do
              sanitized_value
            end
          end

          content.gsub!("{{#{token}}}", sanitized_value)
        end
      end

      content
    end

    def cached?
      Rails.cache.exist?(cache_identifier)
    end

    def get_content
      if !cached?
        http_response = HTTParty.get(url, query: query_params)
        response_received = true if http_response.code == 200
      end

      if !cached? && !response_received
        raise no_response_received(identifier)
      else
        cached_response = Rails.cache.fetch(cache_identifier) do
          http_response.to_json
        end

        @response = json?(cached_response) ? JSON.parse(cached_response) : cached_response
        set_response_attributes!
      end
    end

    def set_response_attributes!
      @content = response['content']
      @chunk_type = response['chunk_type']
      @variable_fallbacks = response['variable_fallbacks'].presence || {}
      @collection_id = response["collection"]["identifier"] if chunk_type == 'collection_item'
      @branch_id = response['branch_id']
    end

  end
end
