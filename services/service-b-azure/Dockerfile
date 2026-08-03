FROM golang:1.26-alpine AS build
WORKDIR /src
# go.mod/go.sum are committed and pin exact dependency versions (including
# transitive ones, via go.sum hashes). "go mod download" only fetches what's
# already resolved and locked here - it never re-resolves versions - so the
# build is reproducible: the same commit always builds the same dependency
# graph, instead of picking up whatever is newest on the day of the build.
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -o /service-b main.go

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /service-b /service-b
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/service-b"]
