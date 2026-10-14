FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils python3 libglu1-mesa && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY .fvmrc ./
RUN version="$(python3 -c 'import json; print(json.load(open(".fvmrc"))["flutter"])')" && git clone --depth 1 --branch "$version" https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"
COPY pubspec.yaml pubspec.lock ./
COPY packages ./packages
RUN flutter pub get
COPY . .
RUN dart run tool/generate.dart && flutter build web --release --no-web-resources-cdn
RUN cd server && dart pub get && dart compile exe bin/server.dart -o /app/5a-ui-server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libstdc++6 && rm -rf /var/lib/apt/lists/* && useradd --uid 10001 --create-home app
WORKDIR /app
COPY --from=build /app/5a-ui-server /app/server
COPY --from=build /app/build/web /app/web
ENV WEB_ROOT=/app/web LOCAL_HOST=0.0.0.0 PORT=5000
USER app
EXPOSE 5000
CMD ["/app/server"]
