# Environment configuration for JuicyFruit API

module Constants
  # Application version
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}

  # General application settings
  ENVIRONMENT = ENV["ENVIRONMENT"]? || "PRODUCTION" # Set to DEVELOPMENT for local testing
  HOST        = ENV["HOST"]? || "127.0.0.1"         # Bind to all interfaces (useful for local dev)
  PORT        = ENV["PORT"]? || "4004"              # Application port
  REUSE_PORT  = ENV["REUSE_PORT"]? || "true"        # Allow port reuse for faster restarts
end
