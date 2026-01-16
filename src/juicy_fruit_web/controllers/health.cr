module JuicyFruitWeb
  module Controllers
    class Health
      include Grip::Controllers::HTTP

      property start_time : Time = Time.utc

      def get(context : Context) : Context
        status = {
          "status"    => "healthy",
          "timestamp" => Time.utc.to_rfc3339,
          "uptime"    => format_duration(Time.utc - start_time),
          "uptimeSeconds" => (Time.utc - start_time).total_seconds.to_i64,
          "version"   => Constants::VERSION,
          "environment" => ENV.fetch("CRYSTAL_ENV", "development"),
          "memory" => {
            "heapSize" => GC.stats.heap_size,
            "freeBytes" => GC.stats.free_bytes,
            "usedBytes" => GC.stats.heap_size - GC.stats.free_bytes,
          },
          "runtime" => {
            "crystal" => Crystal::VERSION,
            "llvm"    => Crystal::LLVM_VERSION,
          },
        }

        context.json(status)
      end

      private def format_duration(span : Time::Span) : String
        days = span.days
        hours = span.hours
        minutes = span.minutes
        seconds = span.seconds

        parts = [] of String
        parts << "#{days}d" if days > 0
        parts << "#{hours}h" if hours > 0
        parts << "#{minutes}m" if minutes > 0
        parts << "#{seconds}s"

        parts.join(" ")
      end
    end
  end
end
