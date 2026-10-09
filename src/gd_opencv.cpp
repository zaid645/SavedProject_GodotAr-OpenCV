#include "gd_opencv.h"

#include <Array.hpp>
#include <Vector3.hpp>

using namespace godot;


// register various functions, variables and signals
void GDOpenCVExample::_register_methods()
{
    register_method("_process", &GDOpenCVExample::_process);
    register_method("set_marker_length", &GDOpenCVExample::set_marker_length);
    register_property<GDOpenCVExample, int>("camera_id", &GDOpenCVExample::set_camera_id, &GDOpenCVExample::get_camera_id, 0);
    register_property<GDOpenCVExample, bool>("show_processed", &GDOpenCVExample::set_show_processed, &GDOpenCVExample::get_show_processed, false);
    register_property<GDOpenCVExample, int>("width", &GDOpenCVExample::width, 640);
    register_property<GDOpenCVExample, int>("height", &GDOpenCVExample::height, 480);
    register_property<GDOpenCVExample, float>("marker_length", &GDOpenCVExample::set_marker_length, &GDOpenCVExample::get_marker_length, 0.05f);
    register_signal<GDOpenCVExample>((char *)"frame_updated", "node", GODOT_VARIANT_TYPE_OBJECT, "image", GODOT_VARIANT_TYPE_OBJECT);
    register_signal<GDOpenCVExample>((char *)"marker_detected",
        "node", GODOT_VARIANT_TYPE_OBJECT,
        "ids", GODOT_VARIANT_TYPE_ARRAY,
        "translations", GODOT_VARIANT_TYPE_ARRAY,
        "rotations", GODOT_VARIANT_TYPE_ARRAY);
}


// constructor
GDOpenCVExample::GDOpenCVExample()
{
}


// destructor
GDOpenCVExample::~GDOpenCVExample()
{
    // release cv::VideoCapture
    if (cap != NULL)
        cap->release();

    // release frame
    if (!frame.empty())
        frame.release();

    // release output
    if (!output.empty())
        output.release();

    // delete pointer to our OpenCV code's object
    delete own_opencv_code_object;
}


// our initializer called by Godot
void GDOpenCVExample::_init()
{
    camera_id              = 0;
    show_processed         = false;
    marker_length          = 0.05f;
    cap                    = NULL;
    width                  = 640;
    height                 = 480;
    own_opencv_code_object = new OpenCVProcessing();
    own_opencv_code_object->set_marker_length(marker_length);
}


// called at every time instant delta by Godot
void GDOpenCVExample::_process(float delta)
{
    // initialize cv::VideoCapture
    if (cap==NULL)
        init_camera();

    // read frame, get output and emit
    if (cap->isOpened())
    {
        if (cap->read(frame))
        {
            output = own_opencv_code_object->process_image(frame, show_processed); // get output from our OpenCV code
            gd_frame = cvMat_to_Image(); // convert to Godot Image
            emit_signal("frame_updated", this, gd_frame);
            emit_marker_signal();
        }
    }
}



// initialize cv::VideoCapture
void GDOpenCVExample::init_camera()
{
    cap = new cv::VideoCapture(camera_id);
    if (cap->isOpened())
    {
        // set frame size
        cap->set(cv::CAP_PROP_FRAME_WIDTH, width);
        cap->set(cv::CAP_PROP_FRAME_HEIGHT, height);
    }
}


// set the camera ID
void GDOpenCVExample::set_camera_id(int cam_id)
{
    camera_id = cam_id;
}


// get the camera ID....not used
int GDOpenCVExample::get_camera_id()
{
    return camera_id;
}


// set show_processed
void GDOpenCVExample::set_show_processed(bool do_process)
{
    show_processed = do_process;
}


// get show_processed....not used
bool GDOpenCVExample::get_show_processed()
{
    return show_processed;
}


// set marker_length (meter) — diteruskan ke OpenCVProcessing
void GDOpenCVExample::set_marker_length(float meters)
{
    marker_length = meters;
    if (own_opencv_code_object != NULL)
        own_opencv_code_object->set_marker_length(meters);
}


// get marker_length
float GDOpenCVExample::get_marker_length()
{
    return marker_length;
}


// emit marker_detected TIAP frame (array kosong = marker hilang,
// agar kubus di Godot bisa disembunyikan, bukan nyangkut)
void GDOpenCVExample::emit_marker_signal()
{
    Array ids;
    Array trans;
    Array rots;

    if (own_opencv_code_object != NULL)
    {
        for (size_t i = 0; i < own_opencv_code_object->last_ids.size(); ++i)
        {
            ids.push_back(own_opencv_code_object->last_ids[i]);

            if (i < own_opencv_code_object->last_tvecs.size() &&
                i < own_opencv_code_object->last_rvecs.size())
            {
                const cv::Vec3d &t = own_opencv_code_object->last_tvecs[i];
                const cv::Vec3d &r = own_opencv_code_object->last_rvecs[i];
                trans.push_back(Vector3(t[0], t[1], t[2]));
                rots.push_back(Vector3(r[0], r[1], r[2]));
            }
        }
    }

    emit_signal("marker_detected", this, ids, trans, rots);
}


// convert cv::Mat to Godot Image
Ref<Image> GDOpenCVExample::cvMat_to_Image()
{
    // convert output from BGR to RGB
    cv::Mat cv_rgb;
    cv::cvtColor(output, cv_rgb, cv::COLOR_BGR2RGB);

    // initialize PoolByteArray
    int numel = cv_rgb.rows * cv_rgb.cols * cv_rgb.channels();
    PoolByteArray bytes;
    bytes.resize(numel);

    // copy data to PoolByteArray
    if (cv_rgb.isContinuous())
    {
        std::memcpy(bytes.write().ptr(), cv_rgb.ptr(), numel);
    }
    else
    {
        // Frame non-continuous: salin per baris dengan offset tujuan yang maju.
        const int row_bytes = cv_rgb.cols * cv_rgb.channels();
        uint8_t *dst = bytes.write().ptr();
        for (int r = 0; r < cv_rgb.rows; ++r)
        {
            std::memcpy(dst + r * row_bytes, cv_rgb.ptr(r), row_bytes);
        }
    }

    // create Godot Image from the PoolByteArray
    Ref<Image> img;
    img.instance();
    img->create_from_data(cv_rgb.cols, cv_rgb.rows, false, img->FORMAT_RGB8, bytes);

    // return
    return img;
}
