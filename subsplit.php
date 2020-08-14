<?php

if ($argc < 6) {
    die(vsprintf("php %s %s %s %s %s %s\n", [
        basename($argv[0]),
        'in_subtitles.vtt (or mask)',
        '10:00:05 (start)',
        '10:04:35 (end)',
        '15 (offset sec)',
        'NEW (out suffix)',
    ]));
}

$inputFiles = [];
foreach (array_slice($argv, 1) as $argument) {
    if (!is_readable($argument)) {
        break;
    }
    $inputFiles[] = $argument;
}

[$start, $end, $offset, $outSuffix] = array_slice($argv, count($inputFiles) + 1);
$start  = (int)str_replace(':', '', $start);
$end    = (int)str_replace(':', '', $end);
$offset = (int)$offset;

if ($start > $end) {
    die("start can't be greater than end\n");
}

foreach ($inputFiles as $in) {
    $split = preg_split(
        '/^(\d[0-9:.]+ --> [0-9:.]+ +.*)$/m',
        implode(PHP_EOL, array_slice(array_map('trim', file($in)), 2)),
        -1,
        PREG_SPLIT_DELIM_CAPTURE | PREG_SPLIT_NO_EMPTY
    );

    $subtitles = array_filter(
        array_combine(
            array_filter($split, function ($n) { return 0 === $n % 2; }, ARRAY_FILTER_USE_KEY),
            array_map('trim', array_filter($split, function ($n) { return 0 !== $n % 2; }, ARRAY_FILTER_USE_KEY))
        ),
        function ($key) use ($start, $end) {
            return preg_match('/(?<sh>\d{2}):(?<sm>\d{2}):(?<ss>\d{2})\.\d* --> (?<eh>\d{2}):(?<em>\d{2}):(?<es>\d{2})/', $key, $m)
                && $start <= (int)($m['sh'] . $m['sm'] . $m['ss'])
                && (int)($m['eh'] . $m['em'] . $m['es']) <= $end;
        },
        ARRAY_FILTER_USE_KEY
    );

    $firstKey  = key($subtitles);
    $inOffset  = explode(':', substr($firstKey, 0, 8));
    $outOffset = $offset - $inOffset[0] * 3600 - $inOffset[1] * 60 - $inOffset[2];

    $content = array_reduce(
        array_keys($subtitles),
        function ($carry, $key) use ($subtitles, $outOffset) {
            $start = explode(':', substr($key, 0, 8));
            $end   = explode(':', substr($key, strpos($key, '-->') + 4, 8));
            foreach ([&$start, &$end] as &$bound) {
                $bound[0] = $bound[0] + (int)($outOffset / 3600);
                $bound[1] = $bound[1] + (int)(($outOffset % 3600) / 60);
                $bound[2] = $bound[2] + (int)($outOffset % 60);

                if ($bound[2] < 0) {
                    $bound[2] += 60;
                    $bound[1] -= 1;
                }
                if ($bound[1] < 0) {
                    $bound[1] += 60;
                    $bound[0] -= 1;
                }

                array_walk($bound, function (&$item) { $item = str_pad($item, 2, 0, STR_PAD_LEFT); });
            }

            $correctedKey = substr_replace($key, implode(':', $start), 0, 8);
            $correctedKey = substr_replace($correctedKey, implode(':', $end), strpos($key, '-->') + 4, 8);

            return $carry . $correctedKey . PHP_EOL . $subtitles[$key] . PHP_EOL . PHP_EOL;
        },
        ''
    );

    file_put_contents(
        substr_replace($in, '_' . $outSuffix, strrpos($in, '.'), 0),
        'WEBVTT' . PHP_EOL . PHP_EOL . rtrim($content)
    );
}