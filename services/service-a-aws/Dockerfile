FROM golang:1.26-alpine AS build
WORKDIR /src
COPY main.go ./
RUN go mod init bridgethegap/service-a && \
    go get github.com/spiffe/go-spiffe/v2@latest && \
    go mod tidy && \
    CGO_ENABLED=0 GOOS=linux go build -o /service-a main.go

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /service-a /service-a
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/service-a"]
