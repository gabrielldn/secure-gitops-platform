FROM golang:1.23.4-alpine3.21 AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /out/demo-app main.go

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /
COPY --from=build /out/demo-app /demo-app
EXPOSE 8080
ENTRYPOINT ["/demo-app"]
