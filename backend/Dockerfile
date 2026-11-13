# Build:  docker build -t owen-tours-api .
# Run:    docker run -p 8080:8080 --env-file .env owen-tours-api
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish src/OwenTours.Api/OwenTours.Api.csproj -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "OwenTours.Api.dll"]
