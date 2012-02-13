module Resque
  module Plugins
    module WaitingRoom
      class MissingParams < RuntimeError; end

      def can_be_performed(params)
        raise MissingParams unless params.is_a?(Hash) && params.keys.sort == [:period, :times]

        @period ||= params[:period]
        @max_performs ||= params[:times].to_i
      end

      def waiting_room_redis_key
        [self.to_s, "remaining_performs"].compact.join(":")
      end

      def before_perform_waiting_room(*args)
        key = waiting_room_redis_key

        if count_key(key, @max_performs)
          performs_left = Resque.redis.decrby(key, 1).to_i

          if performs_left < 1
            Resque.push 'waiting_room', :class => self.to_s, :args => args
            raise Resque::Job::DontPerform
          end
        end
      end

      def count_key(key, number_of_performs)
        # Redis SETNX: sets the keys if it doesn't exist, returns true if key exist
        key_created = !Resque.redis.setnx(key, number_of_performs - 1)
        # Redis EXPIRE: returns TTL or -1 if key doesn't exist/has no ttl
        Resque.redis.expire(key, @period) if key_created

        return key_created
      end

      def repush(*args)
        key = waiting_room_redis_key
        value = Resque.redis.get(key)
        no_performs_left = value && value != "" && value.to_i <= 0
        Resque.push 'waiting_room', class: self.to_s, args: args if no_performs_left

        return no_performs_left
      end
    end
  end
end

