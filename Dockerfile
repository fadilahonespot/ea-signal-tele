# Simple single-stage build for Render deployment
FROM golang:1.22

# Set working directory
WORKDIR /app

# Copy go mod files first for better caching
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOARCH=amd64
RUN go build -o main ./main.go

# Expose port (Render will override this)
EXPOSE 8080

# Run the application
CMD ["./main"]