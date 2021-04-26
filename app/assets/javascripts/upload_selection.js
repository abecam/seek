var upload_url_field;
var keep_title_field;
var examine_url_href;

// Delete after check up!!!
function setup_url_field(examine_url_path,examine_button_id) {
    upload_url_field = $j('#data_url_field');
    keep_title_field = $j('#keep_title_field');

    examine_url_href = examine_url_path;
    $j('#'+examine_button_id).on('click', function(event){
        submit_url_for_examination();
    });
    upload_url_field.on('change', function(event) {
        setTimeout(function(e){
            submit_url_for_examination();
        },0);
        return true;
    });
    upload_url_field.on('keypress',function(event) {
        update_url_checked_status(false);
    });
}
function submit_url_for_examination() {
    disallow_copy_option();
    $j('#test_url_result')[0].innerHTML="<p class='large_spinner'/>";
    var data_url = upload_url_field.val();
    var keep_title = keep_title_field.val();

    $j.post(examine_url_href, { data_url: data_url , keep_title: keep_title}, function(data){} );
}

function allow_copy_option() {
    $j("#copy_option").show();
}

function disallow_copy_option() {
    $j("#copy_option").hide();
    $j("#copy_option input").prop("checked",false);
}

function set_original_filename_for_upload(filename) {
    $j("#original_filename")[0].value=filename;
}

function update_url_checked_status(url_ok) {
    $j("#url_checked")[0].value=url_ok;
    changeUploadButtonText(false);
}

function changeUploadButtonText(isFile) {
    if ($j('[data-upload-button]').length) {
        if (isFile) {
            //data-upload-file-text provides alternative text for when a file is selected
            var text = $j('[data-upload-button]').data('upload-file-text') || 'Upload and Save';
            $j('[data-upload-button]').val(text);
        } else {
            $j('[data-upload-button]').val('Register');
        }
    }
}

$j(document).ready(function () {
    if ($j('#local-file').length) {
        $j('#local-file').on('change', 'input[type=file]', function () { changeUploadButtonText(true); });

        // If the URL field was pre-filled through params, make sure the button text is updated.
        if ($j('#data_url_field').val().length) {
            changeUploadButtonText(false);
        }
    }
});
