#!/usr/bin/env python3
import csv
import os

# Target sample rate (Hz) for combined_interpolated.csv's shared time grid.
# -1 = auto-detect from the densest numeric sensor column; positive number = fixed rate.
INTERPOLATION_RATE_HZ = -1

def _load_sensor_csvs(csv_paths):
    sensors = []
    for path in csv_paths:
        with open(path, newline="") as f:
            reader = csv.reader(f)
            header = next(reader, None)
            if not header or header[0] != "phone_ts_ms":
                continue
            columns = header[1:]
            rows = []
            for row in reader:
                if not row:
                    continue
                try:
                    ts = int(row[0])
                except ValueError:
                    continue
                rows.append((ts, row[1:]))
            sensors.append((columns, rows))
    return sensors

def _combined_header_and_offsets(sensors):
    header = ["phone_ts_ms"]
    offsets = []
    offset = 1
    for columns, _ in sensors:
        offsets.append(offset)
        header.extend(columns)
        offset += len(columns)
    return header, offsets, offset

def _write_combined_raw_csv(sensors, header, offsets, total_columns, output_path):
    all_rows = []
    for sensor_index, (_, rows) in enumerate(sensors):
        for ts, values in rows:
            all_rows.append((ts, sensor_index, values))
    all_rows.sort(key=lambda r: r[0])

    with open(output_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        for ts, sensor_index, values in all_rows:
            row = [""] * total_columns
            row[0] = ts
            start = offsets[sensor_index]
            row[start : start + len(values)] = values
            writer.writerow(row)

def _try_float(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None

def _pchip_interpolate(sample_times, values, query_times):
    n = len(sample_times)
    if n < 2:
        raise ValueError("Need at least 2 points for PCHIP")

    secants = []
    for i in range(n - 1):
        h = sample_times[i + 1] - sample_times[i]
        secants.append((values[i + 1] - values[i]) / h)

    slopes = [0.0] * n
    for i in range(n):
        if i == 0:
            slopes[i] = secants[0]
        elif i == n - 1:
            slopes[i] = secants[n - 2]
        else:
            s1 = secants[i - 1]
            s2 = secants[i]
            if s1 * s2 <= 0:
                slopes[i] = 0.0
            else:
                h1 = sample_times[i] - sample_times[i - 1]
                h2 = sample_times[i + 1] - sample_times[i]
                slopes[i] = (3 * (h1 + h2)) / (h1 / s1 + h2 / s2)

    for i in range(n - 1):
        s = secants[i]
        if s == 0:
            slopes[i] = 0.0
            slopes[i + 1] = 0.0
        else:
            alpha = slopes[i] / s
            beta = slopes[i + 1] / s
            tau = 3 / (abs(alpha + beta) + 1e-14)
            if abs(alpha) > tau:
                slopes[i] = tau * s
            if abs(beta) > tau:
                slopes[i + 1] = tau * s

    segment = 0
    result = []
    for query in query_times:
        while segment < n - 2 and sample_times[segment + 1] < query:
            segment += 1

        t0 = sample_times[segment]
        t1 = sample_times[segment + 1]
        y0 = values[segment]
        y1 = values[segment + 1]
        s0 = slopes[segment]
        s1 = slopes[segment + 1]
        h = t1 - t0
        t = (query - t0) / h

        h00 = (1 + 2 * t) * (1 - t) ** 2
        h10 = t * (1 - t) ** 2
        h01 = t * t * (3 - 2 * t)
        h11 = t * t * (t - 1)

        result.append(h00 * y0 + h10 * h * s0 + h01 * y1 + h11 * h * s1)

    return result

def _dedupe_by_timestamp(times, values):
    out_times, out_values = [], []
    for t, v in zip(times, values):
        if out_times and out_times[-1] == t:
            out_values[-1] = v
        else:
            out_times.append(t)
            out_values.append(v)
    return out_times, out_values

def _write_combined_interpolated_csv(
    sensors, header, offsets, total_columns, output_path, rate_hz_config, label
):
    numeric_cols = {}
    text_cols = {}
    global_min_ts = None
    global_max_ts = None

    for sensor_index, (columns, rows) in enumerate(sensors):
        for col_index in range(len(columns)):
            times, values_str = [], []
            for ts, values in rows:
                if col_index >= len(values) or values[col_index] == "":
                    continue
                times.append(ts)
                values_str.append(values[col_index])
            if not times:
                continue
            times, values_str = _dedupe_by_timestamp(times, values_str)
            if len(times) < 2:
                continue

            global_min_ts = times[0] if global_min_ts is None else min(global_min_ts, times[0])
            global_max_ts = times[-1] if global_max_ts is None else max(global_max_ts, times[-1])

            numeric_values = []
            is_numeric = True
            for v in values_str:
                parsed = _try_float(v)
                if parsed is None:
                    is_numeric = False
                    break
                numeric_values.append(parsed)

            if is_numeric:
                numeric_cols[(sensor_index, col_index)] = (times, numeric_values)
            else:
                text_cols[(sensor_index, col_index)] = (times, values_str)

    if global_min_ts is None:
        print(f"[{label}] No usable data for combined_interpolated.csv, skipping.")
        return

    if rate_hz_config and rate_hz_config > 0:
        rate_hz = float(rate_hz_config)
    else:
        def average_rates(min_samples):
            rates = []
            for times, _ in numeric_cols.values():
                if len(times) < min_samples:
                    continue
                span_s = (times[-1] - times[0]) / 1000.0
                if span_s > 0:
                    rates.append((len(times) - 1) / span_s)
            return rates

        candidates = average_rates(10) or average_rates(2)
        rate_hz = max(candidates) if candidates else 10.0
    print(f"[{label}] combined_interpolated.csv target rate: {rate_hz:.1f} Hz")

    step_ms = 1000.0 / rate_hz
    grid = []
    t = float(global_min_ts)
    while t <= global_max_ts:
        grid.append(t)
        t += step_ms

    interpolated_numeric = {}
    for key, (times, values) in numeric_cols.items():
        first_t, last_t = times[0], times[-1]
        query_indices = [i for i, g in enumerate(grid) if first_t <= g <= last_t]
        if not query_indices:
            continue
        query_times = [grid[i] for i in query_indices]
        interpolated = _pchip_interpolate([float(tt) for tt in times], values, query_times)
        out = [""] * len(grid)
        for idx, val in zip(query_indices, interpolated):
            out[idx] = f"{val:.6f}"
        interpolated_numeric[key] = out

    forward_filled_text = {}
    for key, (times, values) in text_cols.items():
        out = [""] * len(grid)
        j = 0
        current = ""
        for i, g in enumerate(grid):
            while j < len(times) and times[j] <= g:
                current = values[j]
                j += 1
            out[i] = current
        forward_filled_text[key] = out

    with open(output_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        for row_index, g in enumerate(grid):
            row = [""] * total_columns
            row[0] = round(g)
            for sensor_index, (columns, _) in enumerate(sensors):
                base = offsets[sensor_index]
                for col_index in range(len(columns)):
                    key = (sensor_index, col_index)
                    if key in interpolated_numeric:
                        row[base + col_index] = interpolated_numeric[key][row_index]
                    elif key in forward_filled_text:
                        row[base + col_index] = forward_filled_text[key][row_index]
            writer.writerow(row)

def build_combined_outputs(csv_paths, output_dir, label, rate_hz_config=INTERPOLATION_RATE_HZ):
    sensors = _load_sensor_csvs(csv_paths)
    if not sensors:
        return

    os.makedirs(output_dir, exist_ok=True)
    header, offsets, total_columns = _combined_header_and_offsets(sensors)

    raw_path = os.path.join(output_dir, "combined_raw.csv")
    _write_combined_raw_csv(sensors, header, offsets, total_columns, raw_path)
    print(f"[{label}] Combined raw CSV written to {raw_path}")

    interpolated_path = os.path.join(output_dir, "combined_interpolated.csv")
    _write_combined_interpolated_csv(
        sensors, header, offsets, total_columns, interpolated_path, rate_hz_config, label
    )
    print(f"[{label}] Combined interpolated CSV written to {interpolated_path}")
