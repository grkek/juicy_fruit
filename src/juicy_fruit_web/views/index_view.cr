require "ecr"

module JuicyFruitWeb
  module Views
    class Index
      def initialize
      end

      ECR.def_to_s "#{__DIR__}/../templates/index.ecr"
    end
  end
end
