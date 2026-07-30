FROM golang:1.26-alpine AS build
WORKDIR /src
COPY main.go go.mod ./
RUN CGO_ENABLED=0 GOOS=linux go build -o /service-b main.go

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /service-b /service-b
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/service-b"]
