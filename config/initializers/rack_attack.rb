# frozen_string_literal: true

class Rack::Attack
  throttle("api/authenticated", limit: 60, period: 60) do |request|
    request.env["HTTP_AUTHORIZATION"]&.split(" ")&.last if request.path.start_with?("/api/")
  end
end
