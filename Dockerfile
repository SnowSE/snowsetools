# Build stage
FROM elixir:1.19.5-otp-28-alpine AS build

RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

COPY assets assets
COPY config config
COPY lib lib
COPY priv priv

RUN cd assets && npm install
RUN mix compile
RUN mix assets.deploy
RUN mix release

# Runtime stage
FROM elixir:1.19.5-otp-28-alpine AS runtime

RUN apk add --no-cache libgcc libstdc++ ncurses-libs

WORKDIR /app

ENV USER="app"
RUN addgroup -g 1000 $USER && adduser -D -u 1000 -G $USER $USER

COPY --from=build --chown=app:app /app/_build/prod/rel/simple_syllabus_reporter ./

USER app

ENV PHX_SERVER=true
ENV MIX_ENV=prod

EXPOSE 4000

CMD ["bin/simple_syllabus_reporter", "start"]
