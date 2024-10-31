#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <stdbool.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <search.h>

#define DEVICE_PATH "/dev/kallsyms_reader"
#define KALLSYMS_PATH "/proc/kallsyms"
#define FILTER_FUNCTIONS_PATH "/sys/kernel/debug/tracing/available_filter_functions"
#define BUFFER_SIZE 256

ENTRY *filter_functions_ht = NULL;  // Hash table for fast function lookup

// Count the number of lines (functions) in the filter functions file
size_t count_filter_functions() {
    FILE *file = fopen(FILTER_FUNCTIONS_PATH, "r");
    if (!file) {
        perror("Failed to open available_filter_functions");
        return 0;
    }

    size_t count = 0;
    char buffer[BUFFER_SIZE];
    while (fgets(buffer, sizeof(buffer), file)) {
        count++;
    }

    fclose(file);
    return count;
}

// Load available filter functions into a hash table
bool load_filter_functions() {
    FILE *file = fopen(FILTER_FUNCTIONS_PATH, "r");
    if (!file) {
        perror("Failed to open available_filter_functions");
        return false;
    }

    char line[BUFFER_SIZE];
    while (fgets(line, sizeof(line), file)) {
        line[strcspn(line, "\n")] = '\0';  // Remove newline
        ENTRY item = { .key = strdup(line), .data = NULL };
        if (hsearch(item, ENTER) == NULL) {
            perror("Failed to add entry to hash table");
            fclose(file);
            return false;
        }
    }

    fclose(file);
    return true;
}

// Check if a function is available in the filter functions hash table
bool is_function_in_filter(const char *function_name) {
    ENTRY item = { .key = (char *)function_name, .data = NULL };
    return hsearch(item, FIND) != NULL;
}

// Check if the first byte at the given address is `0xE8`
bool check_first_byte_e8(const char *address) {
    int fd = open(DEVICE_PATH, O_RDWR);
    if (fd < 0) {
        perror("Failed to open device");
        return false;
    }

    // Write the address to the kernel module
    if (write(fd, address, strlen(address)) < 0) {
        perror("Failed to write to device");
        close(fd);
        return false;
    }

    // Read the result from the kernel module
    char buffer[BUFFER_SIZE];
    ssize_t ret = read(fd, buffer, sizeof(buffer) - 1);
    if (ret < 0) {
        perror("Failed to read from device");
        close(fd);
        return false;
    }

    buffer[ret] = '\0';  // Null-terminate the string
    close(fd);

    return (strncmp(buffer, "e8", 2) == 0);  // Check if the first byte is `e8`
}

// Clear all addresses that start with `0xE8` by writing zeros to them
void clear_addresses_with_e8() {
    FILE *kallsyms = fopen(KALLSYMS_PATH, "r");
    if (!kallsyms) {
        perror("Failed to open /proc/kallsyms");
        exit(1);
    }

    char line[BUFFER_SIZE];
    unsigned long address;
    char function_name[128];

    while (fgets(line, sizeof(line), kallsyms)) {
        // Extract the address and function name from each line
        if (sscanf(line, "%lx %*c %127s", &address, function_name) == 2) {
            // Check if the function is available in the filter functions
            if (!is_function_in_filter(function_name)) {
                continue;
            }

            // Format the address as a string
            char address_str[20];
            snprintf(address_str, sizeof(address_str), "%lx", address);

            // Check if the first byte is `0xE8`
            if (check_first_byte_e8(address_str)) {
                printf("Clearing address %s (%s)\n", address_str, function_name);

                // Replace the first 5 bytes with `0x00`
                int fd = open(DEVICE_PATH, O_RDWR);
                if (fd < 0) {
                    perror("Failed to open device");
                    continue;
                }

                char input[BUFFER_SIZE];
                snprintf(input, sizeof(input), "%s --replace", address_str);

                // Write the address with the --replace flag to the kernel module
                if (write(fd, input, strlen(input)) < 0) {
                    perror("Failed to write to device");
                }

                close(fd);
            }
        }
    }

    fclose(kallsyms);
}

// Search for addresses with first byte `0xE8` and cross-reference them with filter functions
void search_for_e8() {
    FILE *kallsyms = fopen(KALLSYMS_PATH, "r");
    if (!kallsyms) {
        perror("Failed to open /proc/kallsyms");
        exit(1);
    }

    char line[BUFFER_SIZE];
    unsigned long address;
    char function_name[128];

    while (fgets(line, sizeof(line), kallsyms)) {
        // Extract the address and function name from the line
        if (sscanf(line, "%lx %*c %127s", &address, function_name) == 2) {
            // Check if the function is available in the filter functions
            if (!is_function_in_filter(function_name)) {
                continue;
            }

            // Format the address as a string
            char address_str[20];
            snprintf(address_str, sizeof(address_str), "%lx", address);

            // Check if the first byte is `0xE8`
            if (check_first_byte_e8(address_str)) {
                printf("Address %s (%s)\n", address_str, function_name);
            }
        }
    }

    fclose(kallsyms);
}

int main(int argc, char *argv[]) {
    // Dynamically determine the size of the hash table
    size_t filter_count = count_filter_functions();
    if (filter_count == 0) {
        fprintf(stderr, "No filter functions found or failed to load them.\n");
        return 1;
    }

    // Create the hash table with the required size
    if (hcreate(filter_count) == 0) {
        perror("Failed to create hash table");
        return 1;
    }

    // Load the filter functions into the hash table
    if (!load_filter_functions()) {
        return 1;
    }

    if (argc == 2 && strcmp(argv[1], "--scan") == 0) {
        search_for_e8();
    } else if (argc == 2 && strcmp(argv[1], "--clear") == 0) {
        clear_addresses_with_e8();
    } else if (argc >= 2) {
        char input[BUFFER_SIZE];
        if (argc == 3 && strcmp(argv[2], "--replace") == 0) {
            snprintf(input, sizeof(input), "%s %s", argv[1], argv[2]);
        } else {
            snprintf(input, sizeof(input), "%s", argv[1]);
        }

        int fd = open(DEVICE_PATH, O_RDWR);
        if (fd < 0) {
            perror("Failed to open device");
            return 1;
        }

        // Write the address to the kernel module
        if (write(fd, input, strlen(input)) < 0) {
            perror("Failed to write to device");
            close(fd);
            return 1;
        }

        // Read the result from the kernel module
        char buffer[BUFFER_SIZE];
        ssize_t ret = read(fd, buffer, sizeof(buffer) - 1);
        if (ret < 0) {
            perror("Failed to read from device");
            close(fd);
            return 1;
        }

        buffer[ret] = '\0';  // Null-terminate the string
        printf("%s", buffer);

        close(fd);
    } else {
        fprintf(stderr, "Usage: %s <address> [--replace] | --scan | --clear\n", argv[0]);
        return 1;
    }

    return 0;
}

