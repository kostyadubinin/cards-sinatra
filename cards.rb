require "sinatra"
require "sinatra/cookies"
require "sinatra/reloader" if development?
require "pry" if development?
require "redis"
require "jwt"

get "/" do
  token = cookies[:token]
  logger.info("token=#{token.inspect}")

  begin
    decoded_token = JWT.decode(token, nil, false)
    logger.info("decodedToken=#{decoded_token.inspect}")
    user_id = decoded_token[0]["user_id"]
    logger.info("userId=#{user_id.inspect}")
  rescue JWT::DecodeError => e
    logger.info("error=#{e.class} message=\"#{e.message}\"")
  end

  redis = Redis.new(host: ENV["REDIS_HOST"])
  card_ids = redis.smembers(:cards)

  @cards = card_ids.map do |id|
    card = redis.hgetall("card:#{id}").merge("id" => id)
    left, middle, right = card["front"].split("*")
    { id: id, left: left, middle: middle, right: right, back: card["back"] }
  end

  erb :index
end

post "/cards" do
  redis = Redis.new(host: ENV["REDIS_HOST"])
  id = redis.incr(:next_card_id)
  redis.hmset("card:#{id}", "front", params[:front], "back", params[:back])
  redis.sadd("cards", id)
  redirect "/"
end

delete "/cards/:id" do
  redis = Redis.new(host: ENV["REDIS_HOST"])
  redis.del("card:#{params[:id]}")
  redis.srem("cards", params[:id])
  # TODO: Use `redirect to('/bar')`.
  redirect "/"
end

get "/login" do
  erb :login
end

post "/check-your-inbox" do
  redis = Redis.new(host: ENV["REDIS_HOST"])
  @email = params[:email]

  if redis.hexists(:emails, @email)
    id = redis.hget(:emails, @email)
    logger.info("userId=#{id.inspect} found")
  else
    id = redis.incr(:next_user_id)
    redis.hset(:emails, @email, id)
    redis.hset("user:#{id}", :email, @email)
    logger.info("userId=#{id.inspect} created")
  end

  # TODO: Sign the token.
  token = JWT.encode({ user_id: id }, nil, "none")
  logger.info("token=#{token.inspect}")

  erb :check_your_inbox
end

get "/login-finish" do
  cookies[:token] = params[:token]
  redirect "/"
end
