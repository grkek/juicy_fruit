module JuicyFruitWeb
  module Handlers
    class StaticResource
      include HTTP::Handler

      def call(context : HTTP::Server::Context)
        view = Views::Index.new

        case context.request.path
        when "/"
          context
            .put_resp_header("Content-Type", "text/html")
            .html(view.to_s)
        when "/robots.txt"
          # Disallow all web crawlers from indexing the site
          context
            .put_resp_header("Content-Type", "text/plain")
            .text("User-agent: *\nDisallow: /")
        else
          raise Grip::Exceptions::NotFound.new("Static file not found")
        end
      end
    end
  end
end
