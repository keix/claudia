// Date command - displays the current date and time
const sys = @import("sys");
const utils = @import("shell/utils");

pub fn main(args: *const utils.Args) void {
    _ = args;

    const time = sys.time(null);

    // Convert Unix timestamp to date components
    const seconds_per_minute = 60;
    const seconds_per_hour = 3600;
    const seconds_per_day = 86400;

    // Simple date calculation (assuming Unix epoch starts at 1970-01-01)
    const days_since_epoch = @divTrunc(time, seconds_per_day);
    const remaining_seconds = @mod(time, seconds_per_day);

    const hours = @as(u32, @intCast(@divTrunc(remaining_seconds, seconds_per_hour)));
    const minutes = @as(u32, @intCast(@divTrunc(@mod(remaining_seconds, seconds_per_hour), seconds_per_minute)));
    const seconds = @as(u32, @intCast(@mod(remaining_seconds, seconds_per_minute)));

    // Calculate year, month, day (simplified, doesn't handle leap years perfectly)
    var year: u32 = 1970;
    var days_left = days_since_epoch;

    // Count years
    while (days_left >= 365) {
        if (isLeapYear(year) and days_left >= 366) {
            days_left -= 366;
        } else if (!isLeapYear(year)) {
            days_left -= 365;
        } else {
            break;
        }
        year += 1;
    }

    // Count months
    const days_in_month = [_]u32{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var month: u32 = 1;
    var day: u32 = @intCast(days_left + 1);

    for (days_in_month) |days| {
        var month_days = days;
        if (month == 2 and isLeapYear(year)) {
            month_days = 29;
        }

        if (day > month_days) {
            day -= month_days;
            month += 1;
        } else {
            break;
        }
    }

    // Format and print the date
    var buf: [64]u8 = undefined;
    var pos: usize = 0;

    // Year
    pos += uintToStr(&buf, pos, year);
    buf[pos] = '-';
    pos += 1;

    // Month (with leading zero)
    if (month < 10) {
        buf[pos] = '0';
        pos += 1;
    }
    pos += uintToStr(&buf, pos, month);
    buf[pos] = '-';
    pos += 1;

    // Day (with leading zero)
    if (day < 10) {
        buf[pos] = '0';
        pos += 1;
    }
    pos += uintToStr(&buf, pos, day);
    buf[pos] = ' ';
    pos += 1;

    // Time
    if (hours < 10) {
        buf[pos] = '0';
        pos += 1;
    }
    pos += uintToStr(&buf, pos, hours);
    buf[pos] = ':';
    pos += 1;

    if (minutes < 10) {
        buf[pos] = '0';
        pos += 1;
    }
    pos += uintToStr(&buf, pos, minutes);
    buf[pos] = ':';
    pos += 1;

    if (seconds < 10) {
        buf[pos] = '0';
        pos += 1;
    }
    pos += uintToStr(&buf, pos, seconds);

    // Print the result
    _ = sys.write(1, &buf[0], pos);
    utils.writeStr("\n");
}

fn isLeapYear(year: u32) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

fn uintToStr(buf: []u8, start: usize, value: u32) usize {
    var num = value;
    var digits: [10]u8 = undefined;
    var digit_count: usize = 0;

    // Extract digits in reverse order
    if (num == 0) {
        digits[0] = '0';
        digit_count = 1;
    } else {
        while (num > 0) {
            digits[digit_count] = '0' + @as(u8, @intCast(num % 10));
            num /= 10;
            digit_count += 1;
        }
    }

    // Copy digits in correct order to buffer
    var i: usize = 0;
    while (i < digit_count) : (i += 1) {
        buf[start + i] = digits[digit_count - 1 - i];
    }

    return digit_count;
}
