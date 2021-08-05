/*
 * call peak by MACS2 for ATAC reads
 */
params.options = [:]

include { PAIRTOOLS_SELECT } from '../../modules/nf-core/modules/pairtools/select/main'           addParams(options: params.options.pairtools_select)
include { PAIRTOOLS_SELECT
    as  PAIRTOOLS_SELECT2} from '../../modules/nf-core/modules/pairtools/select/main'           addParams(options: params.options.pairtools_select_short)
include { SHIFTREADS       } from '../../modules/local/atacreads/shiftreads'       addParams(options: params.options.shift_reads)
include { MERGEREADS       } from '../../modules/local/atacreads/mergereads'       addParams(options: params.options.merge_reads)
include { MACS2_CALLPEAK   } from '../../modules/local/atacreads/macs2'            addParams(options: params.options.macs2_atac)
include { DUMPREADS        } from '../../modules/local/atacreads/dumpreads'        addParams(options: params.options.dump_reads_per_group)
include { DUMPREADS
    as DUMPREADS_SAMPLE    } from '../../modules/local/atacreads/dumpreads'        addParams(options: params.options.dump_reads_per_sample)
include { MERGE_PEAK       } from '../../modules/local/atacreads/mergepeak'        addParams(options: params.options.merge_peak)

workflow ATAC_PEAK {
    take:
    raw_pairs  // channel: [ val(meta), [pairs] ]
    macs2_gsize // channel: value

    main:
    // extract ATAC reads, split the pairs into longRange_Trans pairs and short pairs
    ch_version = PAIRTOOLS_SELECT(raw_pairs).version
    PAIRTOOLS_SELECT2(PAIRTOOLS_SELECT.out.selected)
    // shift Tn5 insertion for longRange_Trans pairs
    SHIFTREADS(PAIRTOOLS_SELECT2.out.unselected)
    ch_version = ch_version.mix(SHIFTREADS.out.version)

    // merge the read in same group
    SHIFTREADS.out.bed
            .map{meta, bed -> [meta.group, bed]}
            .groupTuple()
            .map{it -> [[id:it[0]], it[1]]} // id is group
            .set{read4merge}
    MERGEREADS(read4merge)
    ch_version = ch_version.mix(MERGEREADS.out.version)

    // call ATAC narrow peaks for group
    MACS2_CALLPEAK(MERGEREADS.out.bed, macs2_gsize)
    ch_version = ch_version.mix(MACS2_CALLPEAK.out.version)

    // merge peaks
    atac_peaks = MACS2_CALLPEAK.out.peak.map{it[1]}.collect()
    MERGE_PEAK(atac_peaks)

    // dump ATAC reads for each group for maps
    DUMPREADS(MERGEREADS.out.bed)

    // dump ATAC reads for each samples for differential analysis
    DUMPREADS_SAMPLE(SHIFTREADS.out.bed)
    ch_version = ch_version.mix(DUMPREADS.out.version)

    emit:
    peak       = MACS2_CALLPEAK.out.peak       // channel: [ val(meta), path(peak) ]
    xls        = MACS2_CALLPEAK.out.xls        // channel: [ val(meta), path(xls) ]
    mergedpeak = MERGE_PEAK.out.peak           // channel: [ path(bed) ]
    reads      = DUMPREADS.out.peak            // channel: [ val(meta), path(bed) ]
    samplereads= DUMPREADS_SAMPLE.out.peak     // channel: [ val(meta), path(bed) ]
    version    = ch_version                    // channel: [ path(version) ]
}
