#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/device.h>
#include <linux/slab.h>
#include <asm/pgtable.h>  // For page table entry access

#define DEVICE_NAME "kallsyms_reader"
#define CLASS_NAME "kallsyms"
#define BUF_SIZE 64

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Kernel module to read or replace 5 bytes from a given address");

static int major_number;
static struct class *kallsyms_class = NULL;
static struct device *kallsyms_device = NULL;
static char result_buffer[BUF_SIZE];  // Buffer to store the result sent to user
static bool replace_bytes = false;    // Flag indicating if bytes should be replaced

// Disable write protection on the CPU
static void disable_write_protection(void) {
    unsigned long cr0;
    preempt_disable();  // Disable preemption
    barrier();          // Memory barrier
    cr0 = read_cr0();   // Read CR0 register
    clear_bit(16, &cr0);  // Clear the WP (Write Protect) bit
    write_cr0(cr0);     // Write back to CR0
    barrier();          // Memory barrier
}

// Re-enable write protection on the CPU
static void enable_write_protection(void) {
    unsigned long cr0;
    barrier();          // Memory barrier
    cr0 = read_cr0();   // Read CR0 register
    set_bit(16, &cr0);  // Set the WP (Write Protect) bit
    write_cr0(cr0);     // Write back to CR0
    barrier();          // Memory barrier
    preempt_enable();   // Re-enable preemption
}

// Make the page containing the given address writable
static void make_page_writable(unsigned long addr) {
    pte_t *pte;
    unsigned int level;

    // Lookup the PTE for the given address
    pte = lookup_address(addr, &level);
    if (pte) {
        disable_write_protection();
        pte->pte |= _PAGE_RW;  // Set the write bit
        enable_write_protection();
    }
}

// Restore the page permissions to read-only
static void restore_page_permissions(unsigned long addr) {
    pte_t *pte;
    unsigned int level;

    // Lookup the PTE for the given address
    pte = lookup_address(addr, &level);
    if (pte) {
        disable_write_protection();
        pte->pte &= ~_PAGE_RW;  // Clear the write bit
        enable_write_protection();
    }
}

static ssize_t dev_read(struct file *file, char __user *user_buffer, size_t len, loff_t *offset) {
    size_t result_len = strlen(result_buffer);

    if (*offset >= result_len) {
        return 0;  // End of file reached
    }

    if (len > result_len - *offset) {
        len = result_len - *offset;
    }

    if (copy_to_user(user_buffer, result_buffer + *offset, len)) {
        return -EFAULT;
    }

    *offset += len;
    return len;
}

static ssize_t dev_write(struct file *file, const char __user *user_buffer, size_t len, loff_t *offset) {
    unsigned long addr;
    char byte;
    static const char replacement[5] = {0x0f, 0x1f, 0x44, 0x00, 0x00};
    char *input_ptr = result_buffer;  // Pointer to result_buffer for strsep()

    if (len > BUF_SIZE - 1) {
        return -EFAULT;  // Input too large
    }

    if (copy_from_user(result_buffer, user_buffer, len)) {
        return -EFAULT;
    }
    result_buffer[len] = '\0';

    // Extract address and optional "replace" flag
    char *token = strsep(&input_ptr, " ");
    if (kstrtoul(token, 16, &addr)) {
        snprintf(result_buffer, BUF_SIZE, "Invalid address\n");
        return len;
    }

    token = strsep(&input_ptr, " ");
    replace_bytes = (token && strcmp(token, "--replace") == 0);

    if (replace_bytes) {
        make_page_writable(addr);  // Temporarily make the page writable

        disable_write_protection();
        memcpy((void *)addr, replacement, sizeof(replacement));
        enable_write_protection();

        restore_page_permissions(addr);  // Restore the page permissions
        snprintf(result_buffer, BUF_SIZE, "Bytes replaced\n");
    } else {
        result_buffer[0] = '\0';  // Clear the result buffer
        for (int i = 0; i < 5; i++) {
            if (copy_from_kernel_nofault(&byte, (void *)(addr + i), sizeof(byte))) {
                strcat(result_buffer, "?? ");
            } else {
                char byte_str[4];
                snprintf(byte_str, sizeof(byte_str), "%02x ", byte & 0xff);
                strcat(result_buffer, byte_str);
            }
        }
        strcat(result_buffer, "\n");
    }

    return len;
}

static struct file_operations fops = {
    .read = dev_read,
    .write = dev_write,
};

static int __init kallsyms_reader_init(void) {
    printk(KERN_INFO "kallsyms_reader: Module loaded\n");

    major_number = register_chrdev(0, DEVICE_NAME, &fops);
    if (major_number < 0) {
        printk(KERN_ALERT "kallsyms_reader: Failed to register device\n");
        return major_number;
    }

    kallsyms_class = class_create(CLASS_NAME);
    if (IS_ERR(kallsyms_class)) {
        unregister_chrdev(major_number, DEVICE_NAME);
        printk(KERN_ALERT "kallsyms_reader: Failed to create class\n");
        return PTR_ERR(kallsyms_class);
    }

    kallsyms_device = device_create(kallsyms_class, NULL, MKDEV(major_number, 0), NULL, DEVICE_NAME);
    if (IS_ERR(kallsyms_device)) {
        class_destroy(kallsyms_class);
        unregister_chrdev(major_number, DEVICE_NAME);
        printk(KERN_ALERT "kallsyms_reader: Failed to create device\n");
        return PTR_ERR(kallsyms_device);
    }

    return 0;
}

static void __exit kallsyms_reader_exit(void) {
    device_destroy(kallsyms_class, MKDEV(major_number, 0));
    class_destroy(kallsyms_class);
    unregister_chrdev(major_number, DEVICE_NAME);
    printk(KERN_INFO "kallsyms_reader: Module unloaded\n");
}

module_init(kallsyms_reader_init);
module_exit(kallsyms_reader_exit);

