require "../juicy_fruit_web/**"

module JuicyFruit
  class Application
    include Grip::Application

    # The alias is a shortcut to the longer cumbersome name.
    alias Controllers = JuicyFruitWeb::Controllers
    alias Handlers = JuicyFruitWeb::Handlers

    property handlers : Array(HTTP::Handler) = [
      Grip::Handlers::Log.new,
      Grip::Handlers::Exception.new,
      Grip::Handlers::WebSocket.new,
      Grip::Handlers::HTTP.new,
    ] of HTTP::Handler

    property environment : String = Constants::ENVIRONMENT
    property host : String = Constants::HOST
    property port : Int32 = Constants::PORT.to_i
    property? reuse_port : Bool = (Constants::REUSE_PORT || "true") == "true" ? true : false

    def initialize
      # All of the initial connections and setup is defined here.
      routes
    end

    def routes
      forward "/", Handlers::StaticResource

      scope "/api" do
        get "/health", Controllers::Health
      end

      scope "/socket" do
        ws "/debugger", Controllers::Debugger
      end
    end
  end
end
