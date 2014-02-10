#ifndef _DEVICE_WINDOW_CUH_
#define _DEVICE_WINDOW_CUH_

#include <sstream>
#include <cassert>
#include <GL/glew.h>
#include <cuda_gl_interop.h>

#include <thrust/device_vector.h>
#include <thrust/transform.h>

#include "colormap.cuh"
#include "utility.h"

namespace draw
{


/**
 * @brief Draw a Window that uses data from your CUDA computations

 * The aim of this class is to provide an interface to make 
 * the plot of a 2D vector during CUDA computations as simple as possible. 
 * Uses glfw and the cuda_gl_interop functionality
 * @note not tested yet
 */
struct RenderDeviceData
{
    /**
     * @brief Open a window
     *
     * @param width in pixel
     * @param height in pixel
     */
    RenderDeviceData( int rows, int cols) { 
        resource = NULL;
        Nx_ = Ny_ = 0;
        I = rows; J = cols;
        k = 0;
        bufferID = 0;
        cudaGlInit( );
        //glClearColor( 0.f, 0.f, 1.f, 0.f);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    /**
     * @brief free resources
     */
    ~RenderDeviceData( ) {
        if( resource != NULL){
            cudaGraphicsUnregisterResource( resource); 
            //free the opengl buffer
            glDeleteBuffers( 1, &bufferID);
        }
    }
    /**
     * @brief Set up multiple plots in one window
     *
     * After this call, successive calls to the draw function will draw 
     * into rectangular boxes from left to right and top to bottom.
     * @param i # of rows of boxes
     * @param j # of columns of boxes
     * @code 
     * w.set_multiplot( 1,2); //set up two boxes next to each other
     * w.draw( first, 100 ,100, map); //draw in left box
     * w.draw( second, 100 ,100, map); //draw in right box
     * @endcode
     */
    void set_multiplot( unsigned i, unsigned j) { I = i; J = j; k = 0;}
    /**
     * @brief Draw a 2D field in the open window
     *
     * The first element of the given vector corresponds to the bottom left corner. (i.e. the 
     * origin of a 2D coordinate system) Successive
     * elements correspond to points from left to right and from bottom to top.
     * @note If multiplot is set the field will be drawn in the current active 
     * box. When all boxes are full the picture will be drawn on screen and 
     * the top left box is active again. The title is reset.
     * @tparam T The datatype of your elements
     * @param x Elements to be drawn lying on the device
     * @param Nx # of x points to be used ( the width)
     * @param Ny # of y points to be used ( the height)
     * @param map The colormap used to compute color from elements
     */
    template< class T>
    void renderQuad( const thrust::device_vector<T>& x, unsigned Nx, unsigned Ny, draw::ColorMapRedBlueExt& map)
    {
        if( Nx != Nx_ || Ny != Ny_) {
            Nx_ = Nx; Ny_ = Ny;
            cudaGraphicsUnregisterResource( resource);
            //std::cout << "Allocate resources for drawing!\n";
            //free opengl buffer
            GLint id; 
            glGetIntegerv( GL_PIXEL_UNPACK_BUFFER_BINDING, &id);
            bufferID = (GLuint)id;
            glDeleteBuffers( 1, &bufferID);
            //allocate new buffer
            resource = allocateCudaGlBuffer( 3*Nx*Ny);
            glGetIntegerv( GL_PIXEL_UNPACK_BUFFER_BINDING, &id);
            bufferID = (GLuint)id;
        }
        //dg::Timer t;

        unsigned i = k/J, j = k%J;
        //map colors
        //t.tic();
        mapColors( map, x, resource);
        //t.toc();
        //std::cout << "Color mapping took "<<t.diff()*1000.<<"ms\n";
        float slit = 2./500.; //half distance between pictures in units of width
        float x0 = -1. + (float)2*j/(float)J, x1 = x0 + 2./(float)J, 
              y1 =  1. - (float)2*i/(float)I, y0 = y1 - 2./(float)I;
        //t.tic();
        drawTexture( Nx, Ny, x0 + slit, x1 - slit, y0 + slit, y1 - slit);
        //t.toc();
        //std::cout << "Texture mapping took "<<t.diff()*1000.<<"ms\n";
        if( k == (I*J-1) )
            k = 0;
        else
            k++;
    }

  private:
    unsigned I, J, k;
    GLuint bufferID;
    cudaGraphicsResource* resource;  
    unsigned Nx_, Ny_;
    void drawTexture( unsigned Nx, unsigned Ny, float x0, float x1, float y0, float y1)
    {
        // image comes from device resource
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, Nx, Ny, 0, GL_RGB, GL_FLOAT, NULL);
        glLoadIdentity();
        glBegin(GL_QUADS);
            glTexCoord2f(0.0f, 0.0f); glVertex2f( x0, y0);
            glTexCoord2f(1.0f, 0.0f); glVertex2f( x1, y0);
            glTexCoord2f(1.0f, 1.0f); glVertex2f( x1, y1);
            glTexCoord2f(0.0f, 1.0f); glVertex2f( x0, y1);
        glEnd();
    }
    template< class T>
    void mapColors( const draw::ColorMapRedBlueExt& map, const thrust::device_vector<T>& x, cudaGraphicsResource* resource)
    {
        //dg::Timer t;
        draw::Color* d_buffer;
        size_t size;
        //Map resource into CUDA memory space
        //t.tic();
        cudaGraphicsMapResources( 1, &resource, 0);//timing of this may include draw times
        //t.toc();
        //std::cout << "1 took "<<t.diff()*1000.<<"ms\n";
        // get a pointer to the mapped resource
        //t.tic();
        cudaGraphicsResourceGetMappedPointer( (void**)&d_buffer, &size, resource);
        //t.toc();
        //std::cout << "2 took "<<t.diff()*1000.<<"ms\n";
        assert( x.size() == size/3/sizeof(float));
        //t.tic();
        thrust::transform( x.begin(), x.end(), thrust::device_pointer_cast( d_buffer), map);
        //t.toc();
        //std::cout << "3 took "<<t.diff()*1000.<<"ms\n";
        //t.tic();
        //unmap the resource before OpenGL uses it
        cudaGraphicsUnmapResources( 1, &resource, 0);
        //t.toc();
        //std::cout << "4 took "<<t.diff()*1000.<<"ms\n";
    }
    void cudaGlInit( )
    {
        //initialize glew (needed for GLbuffer allocation)
        GLenum err = glewInit();
        if (GLEW_OK != err)
        {
              /* Problem: glewInit failed, something is seriously wrong. */
            std::cerr << "Error: " << glewGetErrorString(err) << "\n";
            return;
        }
        std::cout << "Using GLEW version   " << glewGetString(GLEW_VERSION) <<"\n";

        int device;
        cudaGetDevice( &device);
        std::cout << "Using device number  "<<device<<"\n";
        cudaGLSetGLDevice( device ); 

        cudaError_t error;
        error = cudaGetLastError();
        if( error != cudaSuccess){
            std::cout << cudaGetErrorString( error);}
        glEnable(GL_TEXTURE_2D);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    }

    GLuint allocateGlBuffer( unsigned N)
    {
        GLuint bufferID;
        glGenBuffers( 1, &bufferID);
        glBindBuffer( GL_PIXEL_UNPACK_BUFFER, bufferID);
        // the buffer shall contain a texture 
        glBufferData( GL_PIXEL_UNPACK_BUFFER, N*sizeof(float), NULL, GL_DYNAMIC_DRAW);
        return bufferID;
    }

    //N should be 3*Nx*Ny
    cudaGraphicsResource* allocateCudaGlBuffer( unsigned N )
    {
        cudaGraphicsResource* resource;
        GLuint bufferID = allocateGlBuffer( N);
        //register the resource i.e. tell CUDA and OpenGL that buffer is used by both
        cudaError_t error;
        error = cudaGraphicsGLRegisterBuffer( &resource, bufferID, cudaGraphicsRegisterFlagsWriteDiscard); 
        if( error != cudaSuccess){
            std::cout << cudaGetErrorString( error); return NULL;}
        return resource;
    }
};

} //namespace draw

#endif//_DEVICE_WINDOW_CUH_
