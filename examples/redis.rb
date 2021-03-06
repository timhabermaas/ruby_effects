require 'bundler'

Bundler.setup

require 'eff'
require 'redis'

module RE
  Get = Struct.new(:key)
  Set = Struct.new(:key, :value)

  def self.get(key)
    Eff.send Get.new(key)
  end

  def self.set(key, value)
    Eff.send Set.new(key, value)
  end

  def self.run_with_hash(hash, effect)
    Eff::EffectHandler.with_state
      .on_impure(Get) do |g, k, state|
        value = state[g.key]
        [k.call(value), state]
      end
      .on_impure(Set) do |s, k, state|
        [k.call(nil), hash.merge(s.key => s.value.to_s)]
      end
      .on_pure do |value, state|
        # Return the value and the new
        # state.
        Eff::Freer.return [value, state]
      end
      .run(effect, hash)
  end

  def self.run_with_redis(redis, effect)
    Eff::EffectHandler.new
      .on_impure(Get) do |g, k|
        value = redis.get(g.key)
        k.call(value)
      end
      .on_impure(Set) do |s, k|
        redis.set(s.key, s.value)
        k.call(nil)
      end
      .run(effect)
  end
end

def count_foos_length
  RE.get("foo").bind do |value|
    RE.set("foo_length", value.size).bind do
      Eff::Freer.return value.size
    end
  end
end

def seed_data
  RE.set("foo", "abcdef")
end

# `x>>y` is just `bind` ignoring the passed in value: x.bind { y }
p Eff.run(RE.run_with_hash({}, seed_data >> count_foos_length))
p Eff.run(RE.run_with_redis(Redis.new, seed_data >> count_foos_length))
