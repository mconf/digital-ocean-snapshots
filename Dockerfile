FROM ruby:2.5-slim-buster

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

ENV DEBIAN_FRONTEND noninteractive

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . /app

CMD [ "ruby", "/app/do-snap.rb" ]
