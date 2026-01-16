require "grip"
require "jelly"

require "./constants"
require "./juicy_fruit/**"

# `JuicyFruit` keeps the contexts that define your domain
# and business logic.
#
# Contexts are also responsible for managing your data, regardless
# if it comes from the database, an external API or anything else.
module JuicyFruit; end

# Enable debugging if the application is running in a development environment.
Log.setup(:debug) if Constants::ENVIRONMENT == "DEVELOPMENT"

app = JuicyFruit::Application.new
app.run
